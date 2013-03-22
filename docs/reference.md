
# Lapis 0.2

*work in progress*

Lapis is a web framework written in MoonScript. It is designed to be used with
MoonScript but can also works fine with Lua. Lapis is interesting because it's
built on top of the Nginx distribution [OpenResty][0]. Your web application is
run directly inside of Nginx. Nginx's event loop lets you make asynchronous
HTTP requests, database queries and other requests using the modules provided
with OpenResty. Lua's coroutines allows you to write synchronous looking code
that is event driven behind the scenes.

Lapis is early in development but it comes with a url router, html templating
through a MoonScript DSL, CSRF and session support, a basic Postgres backed
active record system for working with models and a handful of other useful
functions needed for developing websites.

This guide hopes to serve as a tutorial and a reference.

## Basic Setup

Install OpenResty onto your system. If you're compiling manually it's
recommended to enable Postgres and Lua JIT. If you're using heroku then you can
use the Heroku OpenResy module along with the Lua build pack.

Next install Lapis using LuaRocks. You can find the rockspec [on MoonRocks][3]:

    luarocks install --server=http://rocks.moonscript.org/manifests/leafo lapis

## Creating An Application

### `lapis` command line tool

Lapis comes with a command line tool to help you create new projects and start
your server. To see what Lapis can do, run in your shell:

  $ lapis help

For now though, we'll just be creating a new project. Navigate to a clean
directory and run:

  $  lapis new

  ->	wrote	nginx.conf
  ->	wrote	mime.types

Lapis starts you off by writing some basic Nginx configuration. Because your
application runs directly in Nginx, this configuration is what routes requests
from Nginx to your Lua code.

Feel free to look at the generated config file (`nginx.conf` is the only
important file). Here's a brief overview of what it does:

 * Any requests inside `/static/` will serve files out of the directory
   `static` (You can create this directory now if you want)
 * A request to `/favicon.ico` is read from `static/favicon.ico`
 * All other requests will be served by `web.lua`. (We'll create this next)

When you start your server with Lapis, the `nginx.conf` file is actually
processed and templated variables are filled in based on the server's
environment. We'll talk about how to configure these things later on.

### Nginx Configuration

Let's take a look at the configration that `lapis new` has given us. Although
it's not necessary to look at this immediately, it's important to understand
when building more advanced applications or even just deploying your
application to production.

Here is the `nginx.conf` that has been generated:

    worker_processes  ${{NUM_WORKERS}};
    error_log stderr notice;
    daemon off;
    env LAPIS_ENVIRONMENT;

    events {
        worker_connections 1024;
    }

    http {
        include mime.types;

        server {
            listen ${{PORT}};
            lua_code_cache off;

            location / {
                default_type text/html;
                set $_url "";
                content_by_lua_file "web.lua";
            }

            location /static/ {
                alias static/;
            }

            location /favicon.ico {
                alias static/favicon.ico;
            }
        }
    }


The first thing to notice is that this is not a normal Nginx configuration
file. You'll notice special `${{VARIABLE}}` syntax. When starting your server
with Lapis, these variables are replaced with their values pulled from the
active configuration.

The rest of the syntax is regular Nginx configuration syntax.

There are a couple interesting things here. `error_log stderr notice` and
`daemon off` lets our server run in the foreground, and print log text to the
console. This is great for development, but worth turning off in a production
environment.

`lua_code_cache off` is also another setting nice for development. It causes
all Lua modules to be reloaded on each request, so if we change files after
starting the server they will be picked up. Something you also want to turn off
in production for the best performance.

Our single location calls the directive `content_by_lua_file "web.lua"`. This
causes all requests of that location to run through `web.lua`, so let's make
that now.

### A Simple MoonScript Application

Instead of making `web.lua`, we'll actually make `web.moon` and let the
[MoonScript compiler][4] automatically generate the Lua file.

Create `web.moon`:

    lapis = require "lapis"
    lapis.serve class extends lapis.Application
      "/": => "Hello World!"

That's it! `lapis.serve` takes an application class to serve the request with.
So we create an anonymous class that extends from `lapis.Application`.

The members of our class make up the patterns that can be matched against the
route and the resulting action that happens. In this example, the route `"/"`
is matched to a function that returns `"Hello World!"`

The return value of an action determines what is written as the response. In
the simplest form we can return a string in order to write a string.

> Don't forget to compile the `.moon` files. You can watch the current
> directory and compile automatically with `moonc -w`.

## Starting The Server

To start your server you can run `lapis server`. The `lapis` binary will
attempt to find your OpenResty instalation. It will search the following
directories for an `nginx` binary. (The last one represents anything in your
`PATH`)

    "/usr/local/openresty/nginx/sbin/"
    "/usr/sbin/"
    ""

> Remember that you need OpenResty and not a normal installation of Nginx.
> Lapis will ignore regular Nginx binaries.

So go ahead and start your server:

    $ lapis server

We can now navigate to <http://localhost:8080/> to see our application.

## Lapis Applications

Let's start with the basic application from above:

    lapis = require "lapis"
    lapis.serve class extends lapis.Application
      "/": => "Hello World!"

### URL Parameters

Named parameters are a `:` followed by a name. They match all characters
excluding `/`.

    "/user/:name": => "Hello #{@params.name}"


If we were to go to the path "/user/leaf", `@params.name` would be set to
`"leaf"`.

`@params` holds all the parameters to the action. This is a concatenation of
the URL parameters, the GET parameters and the POST parameters.

A splat will match all characters and is represented with a `*`. Splats are not
named. The value of the splat is placed into `@params.splat`

    "/things/*": => "Rest of the url: #{@params.splat}"

### The Action

The action is the method that response to the request for the matched route. In
the above example it uses a fat arrow, `=>`, so you might think that `self` is
an instance of application. But it's not, it's actually an instance of
`Request`, a class that abstracts the request from Nginx.

As we've already seen, the request holds all the parameters in `@params`.

We can the get the distinct parameters types using `@GET`, `@POST`, and
`@url_params`.

We can also access the instance of the application with `@app`, and the raw
request and response with `@req` and `@res`.

### Named Routes

It's useful in websites to give names to your routes so when you need to
generate URLs in other parts of you application you don't have to manually
construct them.

If the key of the action is a table with a single pair, then the key of that
table is the name and the value is the pattern. MoonScript gives us convenient
syntax for representing this:

    [index: "/"]: =>
      @url_for "user_profile", name: "leaf"

    [user_profile: "/user/:name"]: =>
      "Hello #{@params.name}, go home: #{@url_for "index"}" 

We can then generate the paths using `@url_for`. The first argument is the
named route, and the second optional argument is the parameters to the route
pattern.

## HTML Generation

### HTML In Actions

If we want to generate HTML directly in our action we can use the `@html`
method:

    "/": =>
      @html ->
        h1 class: "header", "Hello"
        div class: "body", ->
          text "Welcome to my site!"

HTML templates are written directly as MoonScript code. This is a very powerful
feature (inspirted by [Erector](http://erector.rubyforge.org/)) that gives us
the ability to write templates with high composability and also all the
features of MoonScript. No need to learn any goofy templating syntax with
arbitrary restrictions.

The `@html` method overrides the environment of the function passed to it.
Functions that create HTML tags are generated on the fly as you call them. The
output of these functions is written into a buffer that is compiled in the end
and returned as the result of the action.

Here are some examples of the HTML generation:

    div!                -- <div></div>
    b "Hello World"     -- <b>Hello World</b>
    div "hi<br/>"       -- <div>hi&lt;br/&gt;</div>
    text "Hi!"          -- Hi!
    raw "<br/>"         -- <br/>

    element "table", width: "100%", ->  -- <table width="100%"></table>

    div class: "footer", "The Foot"     -- <div class="footer">The Foot</div>

    div ->                              -- <div>Hey</div>
      text "Hey"

    div class: "header", ->             -- <div class="header"><h2>My Site</h2><p>Welcome!</p></div>
      h2 "My Site"
      p "Welcome!"


### HTML Widgets

The preferred way to write HTML is through widgets. Widgets are classes who are
only concerned with outputting HTML. They use the same syntax as the `@html`
shown above helper for writing HTML.

When Lapis loads a widget automatically it does it by package name. For
example, if it was loading the widget for the name `"index"` it would try to
load the module `views.index`, and the result of that module should be the
widget.

This is what a widget looks like:

    -- views/index.moon
    import Widget from require "lapis.html"

    class Index extends Widget
      content: =>
        h1 class: "header", "Hello"
          div class: "body", ->
            text "Welcome to my site!"


> The name of the widget class is insignificant, but it's worth making one
> because some systems can auto-generate encapsulating HTML named after the
> class.

### Rendering A Widget From An Action

The `render` option key is used to render a widget. For example you can render
the `"index"` widget from our action by returning a table with render set to
the name of the widget:

    "/": =>
      render: "index"

If the action has a name, then we can set render to `true` to load the widget
with the same name as the action:

    [index: "/"]: =>
      render: true


### Passing Data To A Widget

Any `@` variables set in the action can be accessed in the widget. Additionally
any of the helper functions like `@url_for` are also accessible.

    -- web.moon
    [index: "/"]: =>
      @page_title = "Welcome To My Page"
      render: true

    -- views/index.moon
    import Widget from require "lapis.html"

    class Index extends Widget
      content: =>
      h1 class: "header", @page_title
        div class: "body", ->
          text "Welcome to my site!"



[0]: http://openresty.org/
[1]: https://github.com/leafo/heroku-openresty
[2]: https://github.com/leafo/heroku-buildpack-lua
[3]: http://rocks.moonscript.org/modules/leafo/lapis
[4]: http://moonscript.org/reference/#moonc
