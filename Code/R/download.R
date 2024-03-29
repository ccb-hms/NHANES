# pull down the NHANES data

# run in container (must build nhanes-workbench first from this project's Dockerfile):
# docker \
#     run \
#         --rm \
#         --name nhanes-workbench \
#         --platform linux/amd64 \
#         -d \
#         -v /tmp:/HostData \
#         -p 8787:8787 \
#         -p 2200:22 \
#         -p 1433:1433 \
#         -e 'CONTAINER_USER_USERNAME=test' \
#         -e 'CONTAINER_USER_PASSWORD=test' \
#         -e 'ACCEPT_EULA=Y' \
#         -e 'SA_PASSWORD=yourStrong(!)Password' \
#         nhanes-workbench
options(timeout=100)
optionList = list(
  optparse::make_option(c("--container-build"), type="logical", default=FALSE, 
                        help="is this script running inside of a container build process", metavar="logical"),
   
  optparse::make_option(c("--include-exclusions"), type="logical", default=FALSE, 
                        help="whether or not to exclude the tables in Code/R/excluded_tables.tsv", metavar="logical")
); 

optParser = optparse::OptionParser(option_list=optionList);
opt = optparse::parse_args(optParser);

# this variable is used below to determine how to handle errors.
# if running in a container build process, any errors encountered
# in the processing of the files should cause R to return non-zero
# status to the OS, causing the container build to fail.
runningInContainerBuild = opt[["container-build"]]

# parameters to connect to SQL
sqlHost = "localhost"
sqlUserName = "sa"
sqlPassword = "yourStrong(!)Password"
sqlDefaultDb = "master"


# loop waiting for SQL Server database to become available
for (i in 1:60) {
    cn = tryCatch(
        # connect to SQL
        MsSqlTools::connectMsSqlSqlLogin(
            server = sqlHost, 
            user = sqlUserName, 
            password = sqlPassword, 
            database = sqlDefaultDb
        ), warning = function(e) {
            return(NA)
        }, error = function(e) {
            return(NA)
        }
    )
    
    suppressWarnings({
         if (is.na(cn)) {
            Sys.sleep(10)
        } else {
            break
        }
    })
   
}

suppressWarnings({
    if (is.na(cn)) {
        stop("could not connect to SQL Server")
    }
})

# control persistence of downloaded and extracted text files
persistTextFiles = FALSE

outputDirectory = "/NHANES/Data"

fileListTable = nhanesA::nhanesManifest("public")

excludedTables = read.csv("/NHANES/excluded_tables.tsv", sep='\t')
ex <- nhanesA::nhanesManifest("limited")['Table']
reasons <- rep("Limited Access",length(ex))
ex <- cbind(ex, reasons)
colnames(ex)[colnames(ex) == "Table"] ="TableName"
colnames(ex)[colnames(ex) == "reasons"] ="Reason"
excludedTables <- rbind(excludedTables, ex) 

# write the table to file
write.table(
  excludedTables,
  file = "/NHANES/excluded_tables.tsv",
  sep = "\t",
  na = "",
  row.names = FALSE,
  col.names = FALSE,
  quote = FALSE
)

if (!opt[["include-exclusions"]]) {
    fileListTable <- fileListTable[!grepl(paste(excludedTables$TableName, collapse = "|"), fileListTable$'Table'),]
} else{
    fileListTable <- fileListTable[grepl(paste(excludedTables$TableName, collapse = "|"), fileListTable$'Table'),]  
 }

# enumerate distinct data types
fileListTable$"Table" <- strtrim(fileListTable$"Table", 128)
dataTypes = unique(fileListTable$"Table")

# fix case-differing strings
dataTypes = sort(dataTypes)
upperCaseDataTypes = toupper(dataTypes)
uniqueUpper = unique(upperCaseDataTypes)
lapply(uniqueUpper, FUN=function(upperCaseWord){return (max(which(upperCaseDataTypes == upperCaseWord)))})
representativeStringIndex = unlist(lapply(uniqueUpper, FUN=function(upperCaseWord){return (max(which(upperCaseDataTypes == upperCaseWord)))}))
names(uniqueUpper) = dataTypes[representativeStringIndex]
dataTypes = names(uniqueUpper)
names(dataTypes) = uniqueUpper


if (!opt[["include-exclusions"]]){
  # create landing zone for the raw data, set recovery mode to simple
  SqlTools::dbSendUpdate(cn, "CREATE DATABASE NhanesLandingZone")
  SqlTools::dbSendUpdate(cn, "ALTER DATABASE [NhanesLandingZone] SET RECOVERY SIMPLE")
  SqlTools::dbSendUpdate(cn, "USE NhanesLandingZone")
  SqlTools::dbSendUpdate(cn, "CREATE SCHEMA Raw")
  SqlTools::dbSendUpdate(cn, "CREATE SCHEMA Translated")
  SqlTools::dbSendUpdate(cn, "CREATE SCHEMA Metadata")
  SqlTools::dbSendUpdate(cn, "CREATE SCHEMA Ontology")
}

SqlTools::dbSendUpdate(cn, "USE NhanesLandingZone")

# create the ExcludedTables table in SQL
SqlTools::dbSendUpdate(cn, "
    CREATE TABLE NhanesLandingZone.Metadata.ExcludedTables (
        TableName varchar(64),
        Reason varchar(64)
    )
")

# run bulk insert
insertStatement = paste(sep="", "
    BULK INSERT NhanesLandingZone.Metadata.ExcludedTables FROM '/NHANES/excluded_tables.tsv'
    WITH (KEEPNULLS, TABLOCK, ROWS_PER_BATCH=2000, FIRSTROW=2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '\n')")

SqlTools::dbSendUpdate(cn, insertStatement)

# shrink transaction log
SqlTools::dbSendUpdate(cn, "DBCC SHRINKFILE(NhanesLandingZone_log)")

# issue checkpoint
SqlTools::dbSendUpdate(cn, "CHECKPOINT")

# prevent scientific notation
options(scipen = 15)

# track which variables appear in each questionnaire
questionnaireVariables = dplyr::tibble(
  Variable=character(), 
  TableName=character()
)

#--------------------------------------------------------------------------------------------------------
# performance notes for large XPTs:
# 14.6G for a single PAXMIN
# 10G after gc()
# baloons to 32G after second read
# 20G after gc()
# 40 G during bind_rows
# 20 G after rm XPTs and gc()
# 12G file 
#--------------------------------------------------------------------------------------------------------


# enable restart
i=1
downloadErrors = dplyr::tibble(
  DataType=character(), 
  FileUrl=character(), 
  Error=character()
 )

for (i in i:length(dataTypes)) {
    # get the name of the data type
    currDataType = toupper(dataTypes[i])

    # find all rows with URLs that should be relevant to the current data type
    rowsForCurrDataType = which(fileListTable[,"Table"] == currDataType)

    # assemble a list containing all of the subtables for this data type
    dfList = list()

    # pull all of the SAS files for this data type
    for (currRow in rowsForCurrDataType) {

      # get the URL for the SAS file pointed to by the current row
      currFileUrl = fileListTable[currRow, "DataURL"]

      # get the date range for this table
      currYears = fileListTable[currRow, "Years"]

      #TODO move these to the exlusions group above^^^
      cat("reading ", currFileUrl, "\n")

      # attempt to download each file and log errors
      result = tryCatch({
        nhanesA::nhanesFromURL(currFileUrl, translated = FALSE)
      }, warning = function(w) {
        downloadErrors <<- dplyr::bind_rows(
          downloadErrors, 
          dplyr::bind_cols(
            "DataType" = currDataType, 
            "FileUrl" = currFileUrl,
            "Error" = "warning"
          )
        )
        return("warning")
      }, error = function(e) {
        downloadErrors <<- dplyr::bind_rows(
          downloadErrors, 
          dplyr::bind_cols(
            "DataType" = currDataType, 
            "FileUrl" = currFileUrl,
            "Error" = "error"
          )
        )
        return("error")
      })

      if (typeof(result)!='list') {
        next
      }

      # save the survey years in the demographics table
      if (currDataType == "DEMO") {
        years = dplyr::tibble("years" = rep(x=currYears, times=nrow(result)))
        result = dplyr::bind_cols(result, years)
      }

      questionnaireVariables =
        dplyr::bind_rows(
          questionnaireVariables, 
          dplyr::bind_cols( 
            "Variable" = toupper(colnames(result)),
            "TableName" = rep(currDataType, times = ncol(result))
          )
        )

      dfList[[length(dfList) + 1]] = result
      rm(result)
      gc()

      cat("done reading ", currFileUrl, "\n")
    }

    # fix inconsistent types in PSA age variable
    # there are actually two versions of the age variable, 'KID221' and KIQ221
    # not clear whether one or the other is supposed to be double / char from
    # the NHANES documentation
    if (currDataType == "PSA") {
      for (j in 1:length(dfList)) {
        if ("KID221" %in% colnames(dfList[[j]])) {
          dfList[[j]][,"KID221"] = as.character(dfList[[j]][,"KID221"][[1]])
        }
      }
    }

    ## if we were unable to pull any files for this data type, then move on
    if (length(dfList) == 0) {
      next
    }

    # combine the rows from all of the SAS files for this data type
    m = dplyr::bind_rows(dfList)
    rm(dfList)
    gc()

    # if we were able to read a table for this data type
    if (nrow(m) > 0) {

      # get a file system location to save the table
      currOutputFileName = paste(sep = "/", outputDirectory, currDataType)

      # get data types for each column in our current table
      columnTypes = sapply(m, class)

      # identify columns that contain character data
      ixCharacterColumns = which(columnTypes == "character")

      # if we have any character columns
      if (length(ixCharacterColumns) > 0) {

        # iterate over the character columns
        for (currCharColumn in ixCharacterColumns) {

          # fix any embedded line endings
          m[,currCharColumn] = gsub(m[,currCharColumn], pattern = "\r\n", replacement = "", useBytes = TRUE, fixed = TRUE)
        }
      }

      # write the table to file
      write.table(
        m,
        file = currOutputFileName,
        sep = "\t",
        na = "",
        row.names = FALSE,
        col.names = FALSE,
        quote = FALSE
      )

      # generate SQL table definitions from column types in tibbles
      createTableQuery = DBI::sqlCreateTable(DBI::ANSI(), paste("Raw", currDataType, sep="."), m)

      # change TEXT to VARCHAR(256)
      createTableQuery = gsub(createTableQuery, pattern = "\" TEXT", replace = "\" VARCHAR(256)", fixed = TRUE)

      # change DOUBLE to float
      createTableQuery = gsub(createTableQuery, pattern = "\" DOUBLE", replace = "\" float", fixed = TRUE)

      # we know that SEQN and other primary keys should always be an INT
      createTableQuery = gsub(createTableQuery, pattern = "\"SEQN\" float", replace = "\"SEQN\" INT", fixed = TRUE) # nolint
      createTableQuery = gsub(createTableQuery, pattern = "\"SAMPLEID\" float", replace = "\"SAMPLEID\" INT", fixed = TRUE) # nolint
      createTableQuery = gsub(createTableQuery, pattern = "\"DRXFDCD\" float", replace = "\"DRXFDCD\" INT", fixed = TRUE) # nolint
      createTableQuery = gsub(createTableQuery, pattern = "\"DRXMC\" float", replace = "\"DRXMC\" INT", fixed = TRUE) # nolint
      createTableQuery = gsub(createTableQuery, pattern = "\"POOLID\" float", replace = "\"POOLID\" INT", fixed = TRUE) # nolint

      # remove double quotes, which interferes with the schema specification
      createTableQuery = gsub(createTableQuery, pattern = '"', replace = "", fixed = TRUE)

      # create the table in SQL
      SqlTools::dbSendUpdate(cn, createTableQuery)
      
      # run bulk insert
      insertStatement = paste(sep="",
                              "BULK INSERT [NhanesLandingZone].[Raw].",
                              currDataType,
                              " FROM '",
                              currOutputFileName,
                              "' WITH (KEEPNULLS, TABLOCK, ROWS_PER_BATCH=2000, FIRSTROW=1, FIELDTERMINATOR='\t', ROWTERMINATOR = '\n')"
      )

      SqlTools::dbSendUpdate(cn, insertStatement)
      
      indexStatement = paste(sep="",
        "CREATE CLUSTERED COLUMNSTORE INDEX ccix ON Raw.", currDataType)
                              
      SqlTools::dbSendUpdate(cn, indexStatement)

      # if we don't want to keep the derived text files, then delete to save disk space
      if (!persistTextFiles) {
        file.remove(currOutputFileName)
      }
    }

    # keep memory as clean as possible
    rm(m)
    gc()
}

if (!opt[["include-exclusions"]]) {
      # generate CREATE TABLE statement
      createTableQuery = DBI::sqlCreateTable(DBI::ANSI(), "Metadata.QuestionnaireVariables", questionnaireVariables)

      # fix TEXT column types
      createTableQuery = gsub(createTableQuery, pattern = "\" TEXT", replace = "\" VARCHAR(256)", fixed = TRUE)

      # change DOUBLE to float
      createTableQuery = gsub(createTableQuery, pattern = "\" DOUBLE", replace = "\" float", fixed = TRUE)

      # remove double quotes, which interferes with the schema specification
      createTableQuery = gsub(createTableQuery, pattern = '"', replace = "", fixed = TRUE)

      # create the table in SQL
      SqlTools::dbSendUpdate(cn, createTableQuery)
      
      # generate file name for temporary output
      currOutputFileName = paste(sep = "/", outputDirectory, "QuestionnaireVariables.txt")

      # write questionnaireVariables table to disk
      write.table(
        questionnaireVariables,
        file = currOutputFileName,
        sep = "\t",
        na = "",
        append=TRUE,
        row.names = FALSE,
        col.names = FALSE,
        quote = FALSE
      )
        # issue BULK INSERT
      insertStatement = paste(sep="",
                              "BULK INSERT ",
                              "Metadata.QuestionnaireVariables",
                              " FROM '",
                              currOutputFileName,
                              "' WITH (KEEPNULLS, TABLOCK, ROWS_PER_BATCH=2000, FIRSTROW=1, FIELDTERMINATOR='\t')"
      )
      SqlTools::dbSendUpdate(cn, insertStatement)

} else {
      # generate file name for temporary output
      currOutputFileName = paste(sep = "/", outputDirectory, "QuestionnaireVariables.txt")

      # write questionnaireVariables table to disk
      write.table(
        questionnaireVariables,
        file = currOutputFileName,
        sep = "\t",
        na = "",
        append=TRUE,
        row.names = FALSE,
        col.names = FALSE,
        quote = FALSE
      )
        # issue BULK INSERT
      insertStatement = paste(sep="",
                              "BULK INSERT ",
                              "Metadata.QuestionnaireVariables",
                              " FROM '",
                              currOutputFileName,
                              "' WITH (KEEPNULLS, TABLOCK, ROWS_PER_BATCH=2000, FIRSTROW=1, FIELDTERMINATOR='\t')"
      )
      SqlTools::dbSendUpdate(cn, insertStatement)
}

# issue checkpoint
SqlTools::dbSendUpdate(cn, "CHECKPOINT")

# shrink transaction log
SqlTools::dbSendUpdate(cn, "DBCC SHRINKFILE(NhanesLandingZone_log)")

# issue checkpoint
SqlTools::dbSendUpdate(cn, "CHECKPOINT")

if (!opt[["include-exclusions"]]) {
# create a table to hold records of the failed file downloads
SqlTools::dbSendUpdate(cn, "CREATE TABLE Metadata.DownloadErrors (DataType varchar(1024), FileUrl varchar(1024), Error varchar(256))")}

# generate file name for temporary output
currOutputFileName = paste(sep = "/", outputDirectory, "DownloadErrors.txt")

# write failed file downloads table to disk
write.table(
  downloadErrors,
  file = currOutputFileName,
  sep = "\t",
  na = "",
  append=TRUE,
  row.names = FALSE,
  col.names = FALSE,
  quote = FALSE
)

# issue BULK INSERT
insertStatement = paste(sep="",
                        "BULK INSERT ",
                        "Metadata.DownloadErrors",
                        " FROM '",
                        currOutputFileName,
                        "' WITH (KEEPNULLS, TABLOCK, ROWS_PER_BATCH=2000, FIRSTROW=1, FIELDTERMINATOR='\t')"
)

SqlTools::dbSendUpdate(cn, insertStatement)

# shrink transaction log
SqlTools::dbSendUpdate(cn, "DBCC SHRINKFILE(NhanesLandingZone_log)")

# issue checkpoint
SqlTools::dbSendUpdate(cn, "CHECKPOINT")

# shrink tempdb
SqlTools::dbSendUpdate(cn, "USE tempdb")

tempFiles = DBI::dbGetQuery(cn, "
                        SELECT name FROM TempDB.sys.sysfiles
                        ")

for (i in 1:nrow(tempFiles)) {    
    currTempFileName = tempFiles[i,1]
    SqlTools::dbSendUpdate(cn, paste("DBCC SHRINKFILE(",currTempFileName,", 8)", sep=''))
}

# shutdown the database engine cleanly
SqlTools::dbSendUpdate(cn, "SHUTDOWN")