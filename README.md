# shinyLaravelAuth

R-side helpers for authenticating a Shiny app that is embedded in a Laravel/Filament host. It mirrors the [`stats4sd/laravel-shiny-loader`](https://github.com/stats4sd/laravel-shiny-loader) Composer package on the R side.

The app shows **no content** until the Laravel parent confirms the viewer is an authenticated, authorised user and hands over the context data (e.g. which investment to load). There are **no signed tokens** — trust rests on a filesystem shared between the two servers, browser origin checks, and Laravel doing authorisation before it calls back. For the Laravel/Filament side of the handshake — the iframe loader, the origin check, and the authorisation callback — see the companion Composer package [`stats4sd/laravel-shiny-loader`](https://github.com/stats4sd/laravel-shiny-loader).

## Installation

The package lives in its own GitHub repo, [`stats4sd/shiny-laravel-auth`](https://github.com/stats4sd/shiny-laravel-auth). Install it straight from there:

```r
# install.packages("remotes")  # if you don't already have it
remotes::install_github("stats4sd/shiny-laravel-auth")
```

If you manage dependencies with `renv` (recommended for a deployed Shiny app), record it in your lockfile so the deploy installs the same version:

```r
renv::install("stats4sd/shiny-laravel-auth")
renv::snapshot()
```

> Pin a tag or commit for reproducible deploys, e.g. `remotes::install_github("stats4sd/shiny-laravel-auth@v0.1.0")`.

Then load it like any other package:

```r
library(shinyLaravelAuth)   # note: the R package name is camelCase
```

## Usage

The golden rule: **the static UI must contain nothing sensitive.** Anyone can hit the Shiny URL directly, before Laravel has authorised them. So the app you ship is just a shell — a header, a spinner, and an _empty placeholder_. The real content is rendered into that placeholder only when the POST callback from Laravel fires. Three things wire that up:

**1. UI — ship a shell with an empty placeholder.** Inject the message handler in the `<head>`, and reserve a `uiOutput()` slot where the authenticated UI will later be dropped in. Nothing sensitive is defined here.

```r
ui <- dashboardPage(
  dashboardSidebar(
    tags$head(laravel_auth_script()),   # forwards the session id to Laravel
    ...
  ),
  # The real body is rendered into here *after* authentication. Until then it
  # is empty (or you can render a "waiting for authentication…" message).
  uiOutput("authenticated_ui")
)
```

**2. Server — run the handshake, naming the function to call once authenticated.**

```r
server <- function(input, output, session) {
  auth <- laravel_auth(session, on_authenticated = render_authenticated_ui)
  ...
}
```

**3. Server — define `render_authenticated_ui()` and react to the login.** The callback's whole job is to populate the placeholder. A separate `observeEvent(auth$user, ...)` then initialises the app using the context data Laravel posted (`auth$input`).

```r
server <- function(input, output, session) {

  # Sensitive UI is defined *inside* the server and only ever rendered from
  # within this callback — so it cannot reach the browser before auth.
  render_authenticated_ui <- function() {
    output$authenticated_ui <- renderUI({
      dashboardBody(
        h2("Investment dashboard"),
        plotOutput("results"),
        ...the rest of the real app UI...
      )
    })
  }

  auth <- laravel_auth(session, on_authenticated = render_authenticated_ui)

  observeEvent(auth$user, {
    investment_id <- auth$input$investment_id   # keys you POST from Laravel
    ...load data for investment_id and drive the outputs...
  })
}
```

### Why this renders only after authentication

- `render_authenticated_ui()` is passed to `laravel_auth()` as `on_authenticated`. Internally it is called **only inside the `POST` filter** — i.e. the moment Laravel calls back, having already authorised the viewer.
- Because the sensitive UI is built _inside_ `renderUI()` within that callback, it never exists in the page the anonymous visitor first loads. Hitting the Shiny URL directly gives them the empty shell and nothing else.
- Keep `output$authenticated_ui` empty (or a neutral "waiting…" message) until the callback fires. **Do not** put real outputs in the static `ui` object and merely hide them with CSS/`shinyjs` — hidden ≠ absent; the markup and any bootstrapped data would still be in the page source.

> The bundled `render_authenticated_ui` above is deliberately minimal. In a real app it typically also hides a loading spinner and renders the sidebar menu — see `packages/rrm/app.R` in the host project for a full example.

## API

| Function | Purpose |
| --- | --- |
| `laravel_auth_script(app_url)` | `<script>` tag: forwards the session id to the Laravel parent via `postMessage`. `app_url` defaults to `Sys.getenv("LARAVEL_APP_URL")`. |
| `laravel_auth(session, on_authenticated, sessions_dir, base_url, obj_name)` | Server-side handshake. Registers the callback URL, writes it to `sessions_dir/{uuid}`, advertises `{uuid}` to the browser, cleans up on disconnect, and returns a `reactiveValues` with `user` + `input`. |
| `get_post_data(req)` | Parses the JSON body of the callback `POST` into an R list. |

## Configuration

| Env var | Used by | Purpose |
| --- | --- | --- |
| `LARAVEL_APP_URL` | `laravel_auth_script()` | Origin the session id is `postMessage`d to (the host). |
| `URL` | `laravel_auth()` | This Shiny app's own externally reachable base URL. |

The `sessions_dir` (default `../.sessions`) **must be on a volume both the Shiny and Laravel servers can read and write.**

## Data contract

Whatever array the Laravel controller passes to `Http::post($callbackUrl, [...])` arrives in `auth$input` keyed by the same names. Pass **identifiers, never secrets** — authorisation belongs in the Laravel controller, before the callback.

## Notes

- The browser-side origin check lives on the Laravel side (the `<x-shiny-loader::shiny-iframe>` blade component); set `LARAVEL_APP_URL` precisely so messages only go to the trusted host.
- `auth$user` is a constant placeholder (`"authenticated-user"`): Shiny only learns _that_ a request was authorised, not _who_.
