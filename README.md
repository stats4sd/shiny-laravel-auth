# shinyLaravelAuth

R-side helpers for authenticating a Shiny app that is embedded in a
Laravel/Filament host. It mirrors the
[`stats4sd/laravel-shiny-loader`](https://github.com/stats4sd/laravel-shiny-loader)
Composer package on the R side.

The app shows **no content** until the Laravel parent confirms the viewer is an
authenticated, authorised user and hands over the context data (e.g. which
investment to load). There are **no signed tokens** — trust rests on a
filesystem shared between the two servers, browser origin checks, and Laravel
doing authorisation before it calls back. For the full end-to-end narrative of
the handshake, see [`packages/rrm/README-auth.md`](../rrm/README-auth.md).

## Installation

```r
# from the monorepo root
remotes::install_local("packages/shinyLaravelAuth")
# or, once it has its own remote:
# remotes::install_github("stats4sd/shinyLaravelAuth")
```

## Usage

Three lines wire it into a Shiny app.

**1. UI** — inject the message handler in the head:

```r
dashboardSidebar(
  tags$head(laravel_auth_script()),
  ...
)
```

**2. Server** — run the handshake, saying what to do once authenticated:

```r
auth <- laravel_auth(session, on_authenticated = render_authenticated_ui)
```

**3. Server** — react to a confirmed login:

```r
observeEvent(auth$user, {
  investment_id <- auth$input$investment_id   # keys you POST from Laravel
  ...initialise the app...
})
```

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

The `sessions_dir` (default `../.sessions`) **must be on a volume both the Shiny
and Laravel servers can read and write.**

## Data contract

Whatever array the Laravel controller passes to `Http::post($callbackUrl, [...])`
arrives in `auth$input` keyed by the same names. Pass **identifiers, never
secrets** — authorisation belongs in the Laravel controller, before the callback.

## Notes

- The browser-side origin check lives on the Laravel side (the
  `<x-shiny-loader::shiny-iframe>` blade component); set `LARAVEL_APP_URL`
  precisely so messages only go to the trusted host.
- `auth$user` is a constant placeholder (`"authenticated-user"`): Shiny only
  learns *that* a request was authorised, not *who*.
