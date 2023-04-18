# add empty .domo_env as parent
.domo_env <- new.env()

.onLoad <- function(libname, pkgname) {
        packageStartupMessage("Welcome to bi.r")
}

load(domoCustomer)
load(domoAccessToken)

init(Sys.getenv('DOMO_BASE_URL'), Sys.getenv('DEVELOPER_TOKEN'))
ds <- fetch('8df653c5-d368-4a5e-ba83-0a912fd405db')
