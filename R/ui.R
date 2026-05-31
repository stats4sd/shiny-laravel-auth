#' Browser-side Laravel auth handshake script
#'
#' Returns a `<script>` tag that registers a Shiny custom message handler named
#' `"session"`. When the Shiny server sends the session id (via
#' [laravel_auth()]), the handler forwards it to the Laravel parent window with
#' `parent.postMessage()`, targeting `app_url` as the message origin.
#'
#' Drop the returned tag into the app's `<head>`, e.g.
#' `tags$head(laravel_auth_script())`.
#'
#' @param app_url Origin the session id is posted to (the Laravel host). Defaults
#'   to the `LARAVEL_APP_URL` environment variable.
#'
#' @return A [shiny::tags] `script` node.
#' @export
#'
#' @examples
#' \dontrun{
#' shiny::tags$head(laravel_auth_script())
#' }
laravel_auth_script <- function(app_url = Sys.getenv("LARAVEL_APP_URL")) {
  shiny::tags$script(shiny::HTML(paste0(
    'Shiny.addCustomMessageHandler("session", function(message) {\n',
    '   parent.postMessage(message, "', app_url, '")\n',
    '});'
  )))
}
