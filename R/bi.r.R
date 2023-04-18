# Stuff to setup Domo access
#####

# add empty .domo_env as parent
.domo_env <- new.env()

.onLoad <- function(libname, pkgname) {
        packageStartupMessage("Welcome to bi.r your home for BI stuff")
}

customer <- load('domoCustomer')
token <- load('domoAccessToken')

#' create domo environment and store login info
#'
#' @param customer The customer ID or base URL.  e.g.  acme.domo.com  or  acme
#' @param token The DEV token required for API access.
#' @export
#' @examples
#' init(Sys.getenv('DOMO_BASE_URL'), Sys.getenv('DEVELOPER_TOKEN'))
init <- function(customer,
                 token,
                 config = NULL,
                 verbose = FALSE) {

  .domo_env$customer <- customer
  .domo_env$customer.url <-
    paste0("https://", customer, '.domo.com')
  .domo_env$auth.token <- c('X-DOMO-Developer-Token' = token)
  .domo_env$user.agent <- c("User-Agent" = "DomoR-test/1.0")
  if (is.null(config)) {
    if (verbose == TRUE) {
      assign("config", c(verbose = TRUE), .domo_env)
    }
    else {
      assign("config", c(), .domo_env)
    }
  }
  else {
    assign("config", config, .domo_env)
  }
}

init(customer, token)
#####

