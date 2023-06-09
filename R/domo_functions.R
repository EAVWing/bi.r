#' Fetch a data source.
#'
#' Retrieves a data source by ID (GUID) or by
#' previous list() index from Domo,
#' converts it to a data.frame and returns.
#'
#' @param id A data source id (GUID) or an index from a previous list.
#' @param columns A vector of column names to return from the Domo datasource. (not case sensitive)
#' @param ... Additional httr options
#' @return A \code{data.frame} built from the requested Domo data source.
#' @export
#' @examples
#' DomoR::init(Sys.getenv('DOMO_BASE_URL'), Sys.getenv('DEVELOPER_TOKEN'))
#' df <- DomoR::fetch('4826e3fb-cd23-468d-9aff-96bf5b690247')
#' DomoR::list_ds(limit=10)
#' df <- DomoR::fetch(1)
#' df <- DomoR::fetch('4826e3fb-cd23-468d-9aff-96bf5b690247',
#'   c('accountid', 'lastname', 'startdate'),
#'   httr::progress())
fetch <- function(id, columns = NULL, use.make.names=FALSE, guessEncoding=TRUE, ...) {

        domo_ds_url <- paste0(paste0("https://", customer, '.domo.com'), '/api/data/v2/datasources/', id, '/dataversions/latest?includeHeader=true')

        all.headers <- httr::add_headers(c(.domo_env$auth.token, .domo_env$user.agent,
                                           'Accept'='text/csv'))

        get_result <- httr::GET(domo_ds_url, all.headers, .domo_env$config, ...)

        # handle errors
        httr::stop_for_status(get_result)

        if(guessEncoding){
                guessEncoding <- readr::guess_encoding(get_result$content)
        }else{
                guessEncoding <- NULL;
        }

        if(is.null(guessEncoding)){
                guessEncodingValue <- 'UTF-8'
        }else{
                guessEncodingValue <- guessEncoding$encoding[1]
                if(guessEncodingValue=='ASCII'){
                        guessEncodingValue <- 'UTF-8'
                }
        }

        df <- httr::content(get_result,na=c('\\N'),encoding=guessEncodingValue, ...) # type="domo/csv"

        if(use.make.names){
                names(df) <- make.names(tolower(names(df)))
        }

        return(data.frame(df))
}

#' Create a data source from a data.frame
#'
#' @param data A data.frame from which to create the dataset
#' @param name Name to assign the dataset on Domo
#' @param description Optional description of the dataset
#' @export
#' @examples
#' df <- data.frame(matrix(rnorm(20), nrow=10))
#' DomoR::create(df, name="My Data Source Name", description="My Data Source Description")
create <- function(data, name, description='') {

        # check that required env variables exist
        if(!exists("customer", .domo_env) || !exists("auth.token", .domo_env)) {
                stop("Both a customer instance and token are required, please set with 'DomoR::init('customer', 'token')'")
        }

        if(missing(name)) {
                warning('Data source will be created without a name')
        }

        if(missing(description)) {
                warning('Data source will be created without a description')
        }

        schema <- schema_definition(data)

        json <- list(transport=list(type="API"), dataSource=list(name=name, description=description),
                     dataProvider=list(key="r", name="R"), schemaDefinition=list(columns=schema$columns))

        body <- jsonlite::toJSON(json,auto_unbox=T)

        all.headers <- httr::add_headers(c(.domo_env$auth.token, .domo_env$user.agent,
                                           'Content-Type'='application/json',
                                           'Accept'='application/json'))

        # issue request
        create_result <- httr::POST(paste0(.domo_env$customer.url, '/api/data/v1/streams'),
                                    body=body, all.headers, .domo_env$config)

        httr::stop_for_status(create_result)

        # get the data source id
        create_json <- httr::content(create_result)

        ds <- create_json$dataSource$id
        #message(paste('Created datasource: ', ds))

        #use replace function to upload data.
        out <- DomoR::replace_ds(ds,data)
        return(ds)
}

#' Replace a data source from a data.frame
#'
#' @param data_source_id A GUID corresponding to the datasource ID from Domo.
#' @param data A data.frame from which to create a data source.
#' @param ... Additional curl and httr parameters
#' @export
#' @examples
#' DomoR::init(Sys.getenv('DOMO_BASE_URL'), Sys.getenv('DEVELOPER_TOKEN'))
#' df <- data.frame(matrix(rnorm(20), nrow=10))
#' DomoR::replace_ds(data_source_id,df)
replace_ds <- function(data_source_id,data,...) {

        # check that required env variables exist
        if(!exists("customer", .domo_env) || !exists("auth.token", .domo_env)) {
                stop("Both a customer instance and token are required, please set with 'DomoR::init('customer', 'token')'")
        }

        domoSchema <- jsonlite::toJSON(list(columns=schema_domo(data_source_id)),auto_unbox = T)
        #print(paste("SCHEMA DOMO",domoSchema))
        dataSchema <- jsonlite::toJSON(list(columns=schema_data(data)))
        #print(paste("SCHEMA DATA",dataSchema))

        stream_id <- lookup_stream(data_source_id)$id

        if(!(identical(domoSchema,dataSchema))){

                headers <- httr::add_headers(c(.domo_env$auth.token, .domo_env$user.agent,'Content-Type'='application/json','Accept'='application/json'))

                body <- jsonlite::toJSON(list( # id=stream_id,
                        schemaDefinition=list(columns=schema_definition(data)$columns)), auto_unbox = T)

                create_result <- httr::PUT(paste0(.domo_env$customer.url, '/api/data/v1/streams/', stream_id),
                                           body=body, headers, .domo_env$config)

                httr::stop_for_status(create_result)

                warning('schema changed')
        }

        exec_id <- start_execution(stream_id)

        total_rows <- nrow(data)

        CHUNKSZ <- estimate_rows(data)
        start <- 1
        end <- total_rows
        part <- 1
        repeat {
                if (total_rows - end > CHUNKSZ) {
                        end <- start + CHUNKSZ
                } else {
                        end <- total_rows
                }
                data_frag <- data[start:end,]
                #uploadPart (id, uploadId, part, data_frag)

                systemInfo <- Sys.info()[["sysname"]]

                if(!is.null(systemInfo) & identical("windows", tolower(systemInfo))){
                        uploadPart (stream_id, exec_id, part, data_frag)
                }else{
                        uploadPartStr (stream_id, exec_id, part, data_frag)
                }
                part <- part + 1
                start <- end + 1
                if (start >= total_rows)
                        break
        }

        result <- commitStream(stream_id, exec_id)
}

estimate_rows <- function (data, kbytes = 10000) {
        sz <- pryr::object_size(data)
        targetSize <- kbytes * 3 # compression factor
        if (sz / 1000 > targetSize)
                return(floor(nrow(data)*(targetSize) / (sz/1000)))
        return(nrow(data))
}

uploadPartStr <- function (stream_id, exec_id, part, data) {
        FNAME <- tempfile(pattern="domo", fileext=".gz")

        put_url <- paste0(.domo_env$customer.url, "/api/data/v1/streams/", stream_id, "/executions/", exec_id, "/part/", part)

        all.headers <- httr::add_headers(c(.domo_env$auth.token, .domo_env$user.agent,
                                           'Content-Type'='text/csv', 'Content-Encoding'='gzip'))

        z <- gzfile(FNAME, "wb")

        if((Sys.getenv("DOMOR_OUTPUT_ENCODING") == "") | is.null(Sys.getenv("DOMOR_OUTPUT_ENCODING"))){
                write.table(data, file=z, col.names=FALSE, row.names=FALSE, sep=',', na='\\N', qmethod="double")
        }else{
                encoding <- Sys.getenv("DOMOR_OUTPUT_ENCODING")
                print(paste("Encoding used: ", encoding))
                write.table(data, file=z, col.names=FALSE, row.names=FALSE, sep=',', na='\\N', qmethod="double", fileEncoding=encoding)
        }

        close(z)

        size <- file.info(FNAME)$size
        b <- readBin(f <- file(FNAME, "rb"), "raw", n=size)
        close(f)

        result <- httr::PUT(put_url, body=b, all.headers, .domo_env$config)
        unlink(FNAME)
        json_result <- httr::content(result)
        stopifnot(json_result$status == 200)
}

uploadPart <- function (stream_id, exec_id, part, data) {
        FNAME <- tempfile(pattern="domo", fileext=".gz")

        put_url <- paste0(.domo_env$customer.url, "/api/data/v1/streams/", stream_id, "/executions/", exec_id, "/part/", part)

        all.headers <- httr::add_headers(c(.domo_env$auth.token, .domo_env$user.agent,
                                           'Content-Type'='text/csv', 'Content-Encoding'='gzip'))

        z <- gzfile(FNAME, "wb")

        readr::write_csv(data,file=z,col_names=FALSE,na='\\N')

        close(z)

        size <- file.info(FNAME)$size
        b <- readBin(f <- file(FNAME, "rb"), "raw", n=size)
        close(f)

        result <- httr::PUT(put_url, body=b, all.headers, .domo_env$config)
        unlink(FNAME)
        json_result <- httr::content(result)
        stopifnot(json_result$status == 200)
}

commitStream <- function(stream_id, exec_id) {
        commit_url <- paste0(.domo_env$customer.url, "/api/data/v1/streams/", stream_id, "/executions/", exec_id, "/commit")
        all.headers <- httr::add_headers(c(.domo_env$auth.token, .domo_env$user.agent, "Content-Type"="application/json"))

        result <- httr::PUT(commit_url, all.headers, .domo_env$config)
        #result$status_code
        httr::content(result)
}

delete_ds <- function (id) {
        del_url <- paste0(.domo_env$customer.url, "/api/data/v3/datasources/", id, "?deleteMethod=hard")
        http.headers <- httr::add_headers(c(.domo_env$auth.token, .domo_env$user.agent))
        result <- httr::DELETE(del_url, http.headers, .domo_env$config)
        httr::content(result)
}

start_execution <- function(stream_id) {
        url <- paste0(.domo_env$customer.url, "/api/data/v1/streams/", stream_id, "/executions")
        http.headers <- httr::add_headers(c(.domo_env$auth.token, .domo_env$user.agent))
        result <- httr::POST(url, http.headers, .domo_env$config)
        x <- httr::content(result)
        x$executionId
}


convertDomoDateTime <- function(v) {

        date_time <- tryCatch({ as.POSIXct(strptime(v,"%Y-%m-%dT%H:%M:%S")) }, error = function(err) { NA })
        if (is.na(date_time[1]))
                date_time <- tryCatch({ as.POSIXct(strptime(v,"%Y-%m-%d %H:%M:%S")) }, error = function(err) { NA })
        if (is.na(date_time[1]))
                date_time <- tryCatch({ as.Date(v) }, error = function(err) { NA })

        return(date_time)
}
