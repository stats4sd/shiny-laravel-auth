#' Run the server-side Laravel <-> Shiny authentication handshake
#'
#' Call this once inside the Shiny server function. It:
#' \enumerate{
#'   \item registers a private data object, minting a unique callback URL
#'         `/session/{uuid}/dataobj/{id}` whose filter responds to a `POST`;
#'   \item writes that callback URL to `{sessions_dir}/{uuid}` — a file on a
#'         volume shared with Laravel, so Laravel can find where to call back;
#'   \item sends `{uuid}` to the browser via the `"session"` custom message
#'         (handled by [laravel_auth_script()]), which posts it up to Laravel;
#'   \item removes the session file when the Shiny session ends.
#' }
#'
#' When Laravel has authorised the user it `POST`s the context data back to the
#' callback URL. That `POST` triggers the filter: `on_authenticated()` is called,
#' the posted body is parsed into `auth$input`, and `auth$user` is set — so an
#' `observeEvent(auth$user, ...)` can initialise the app using `auth$input`.
#'
#' There are no signed tokens: trust rests on the shared filesystem (only this
#' process can create a given `{uuid}` file), browser origin checks on the
#' Laravel side, and Laravel performing authorisation before it calls back.
#'
#' @param session The Shiny `session` object.
#' @param on_authenticated Optional zero-argument function called inside the
#'   `POST` filter the moment authentication is confirmed — e.g. to swap the
#'   pre-auth UI for the real UI. Keeps this package UI-agnostic.
#' @param sessions_dir Directory holding the per-session callback files. Must be
#'   readable/writable by both the Shiny and Laravel processes. Defaults to
#'   `"../.sessions"`.
#' @param base_url This Shiny app's externally reachable base URL, prepended to
#'   the callback path that Laravel will `POST` to. Defaults to the `URL`
#'   environment variable.
#' @param obj_name Name passed to `session$registerDataObj()`; parameterised so
#'   multiple apps can coexist under one `sessions_dir`.
#'
#' @return A [shiny::reactiveValues] object with `user` and `input` fields,
#'   populated once Laravel posts back.
#' @export
#'
#' @examples
#' \dontrun{
#' # The static UI ships an empty placeholder; nothing sensitive lives here.
#' ui <- fluidPage(tags$head(laravel_auth_script()), uiOutput("authenticated_ui"))
#'
#' server <- function(input, output, session) {
#'   # Defined inside the server and rendered only from this callback, so the
#'   # real UI never reaches an unauthenticated browser.
#'   render_authenticated_ui <- function() {
#'     output$authenticated_ui <- renderUI(plotOutput("results"))
#'   }
#'
#'   auth <- laravel_auth(session, on_authenticated = render_authenticated_ui)
#'
#'   observeEvent(auth$user, {
#'     investment_id <- auth$input$investment_id
#'     # ...initialise the app for investment_id...
#'   })
#' }
#' }
laravel_auth <- function(session,
                         on_authenticated = NULL,
                         sessions_dir = "../.sessions",
                         base_url = Sys.getenv("URL"),
                         obj_name = "auth") {
  auth <- shiny::reactiveValues()

  # A POST to this URL means Laravel has authorised the user and is handing
  # over the context data.
  auth_url <- session$registerDataObj(
    name = obj_name,
    data = list(),
    filter = function(data, req) {
      if (identical(req$REQUEST_METHOD, "POST")) {
        if (is.function(on_authenticated)) on_authenticated()

        # Set input before user: an observeEvent(auth$user) with req(auth$input)
        # must see input already populated.
        auth$input <- get_post_data(req)
        auth$user <- "authenticated-user"

        return(shiny::httpResponse(200, "text/plain", "Message received - from Shiny"))
      }
    }
  )

  # /session/{uuid}/dataobj/{id}  ->  {uuid}
  session_uuid <- sub("/dataobj/.*", "", sub("^session/", "", auth_url))
  session_file <- file.path(sessions_dir, session_uuid)

  # Hand Laravel the full callback URL by writing it to the shared file.
  conn <- file(session_file)
  writeLines(paste0(base_url, "/", auth_url), conn)
  close(conn)

  # Tell the browser the session id so it can postMessage it to Laravel.
  session$sendCustomMessage("session", session_uuid)

  # Clean up the shared file so .sessions/ does not grow unbounded.
  session$onSessionEnded(function() {
    if (file.exists(session_file)) unlink(session_file)
  })

  auth
}

#' Parse the body of a JSON POST sent to a registerDataObj URL
#'
#' Reads the raw Rook request body, un-escapes Unicode, strips CRLF noise, and
#' parses it as JSON. Laravel's `Http::post($url, $array)` sends a JSON body by
#' default, so the posted array arrives keyed by the same names.
#'
#' @param req A Rook request, as passed to a `session$registerDataObj()` filter.
#'
#' @return The parsed body as an R list (via [jsonlite::fromJSON]).
#' @export
get_post_data <- function(req) {
  req$rook.input$rewind()
  body <- rawToChar(req$rook.input$read(-1))
  body <- stringi::stri_unescape_unicode(body)
  body <- stringr::str_replace_all(body, "\r\n", "")
  jsonlite::fromJSON(body)
}
