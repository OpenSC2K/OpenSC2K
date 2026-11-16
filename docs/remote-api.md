# Remote API

A program outside the game can play OpenSC2K through a local port. The purpose is
tests and development with an LLM agent: the agent starts a city, builds, runs the
simulation, answers each window and reads the result, without control of the mouse
of the computer. The game can run without a window, or with its window so that a
person watches what the agent does.

The remote API runs JavaScript in the console script runtime. Thus it has the same
functions as [scripts](scripting.md), and the functions that control the interface
and the input. `game/assets/scripting/remote-api.md` is the guide for the agent. The
game serves it on `/guide`.

- [Start the game](#start-the-game)
- [Routes](#routes)
- [Scripts of a request](#scripts-of-a-request)
- [Model Context Protocol](#model-context-protocol)
- [What an agent can do](#what-an-agent-can-do)
- [Headless and windowed games](#headless-and-windowed-games)
- [Safety](#safety)
- [Code layout](#code-layout)

## Start the game

The server is off by default. Start it in one of these ways:

- `tools/remote_game.py start` starts the game and waits until the port answers.
- Start the game with `--api` (port 9240) or `--api=PORT`:
  `godot --path game -- --api`
- Type `api` or `api <port>` in the Console. `api off` stops the server.

`tools/remote_game.py` is the shell client:

```sh
tools/remote_game.py start                 # a headless game
tools/remote_game.py start --window        # a game with its window
tools/remote_game.py eval 'game.newCity({ name: "Springfield", seed: 7 })'
tools/remote_game.py eval - < script.js    # a script from standard input
tools/remote_game.py state
tools/remote_game.py city-data --cell 40 40             # each value of one tile, as JSON
tools/remote_game.py city-data --area 40 40 8 8 --fields structure,zone
tools/remote_game.py screenshot screen.png --scale 0.5
tools/remote_game.py city-image part.png --area 40 40 12 12 --size large
tools/remote_game.py control-image tile.png --scale 4   # the canvas of the SCURK editor
tools/remote_game.py guide
tools/remote_game.py stop
```

`start` uses a disposable profile and the packs in `ext/`: the settings and the
cities of the player do not change. `--profile player` uses the normal profile.
`--port` or the environment variable `OPENSC2K_API_PORT` selects another port, thus
more than one game can run. The game plays no sound. `eval` exits with status 1
when the script failed.

## Routes

The server listens on `127.0.0.1` only.

| Route | Answer |
| --- | --- |
| `GET /` | The routes, as JSON. |
| `POST /eval` | Runs the JavaScript of the body. The body is the source, or JSON `{ "source": "...", "timeout": 30000 }` with the content type `application/json`. `?timeout=` gives the time in milliseconds for plain source. |
| `GET /state` | The value of `game.state()`. |
| `GET /city-data` | The city as JSON, without an image. `?x=40&y=40` gives each value of one tile (`city.cell`). `?x=40&y=40&width=8&height=8` gives the tiles of an area, and no query gives the whole city with `city.info()` and `city.census()` (`city.cells`). `fields=structure,zone` selects values; `format` is `cells` or `columns`; `empty=true` keeps the empty values of a cell. The answer is `{ ok, value, error, console }`. |
| `GET /screenshot` | A PNG image of the game window. `?scale=0.5` makes it smaller. A headless game answers 503. |
| `GET /city-image` | A PNG image of the city, also from a headless game. `?x=40&y=40&width=12&height=12` gives only those tiles. `size` is `small`, `medium` or `large`; `view` is `city` or `underground`. |
| `GET /control-image` | A PNG picture of a control that draws its content, such as the canvas of the SCURK editor, also from a headless game. `target` is the id or the name of the control; without it, the first such control of the top window. `scale` makes each pixel larger, from 1 to 16. |
| `GET /guide` | The guide for an agent. |
| `GET /types` | The TypeScript declarations of the API. |
| `POST /mcp` | The Model Context Protocol. |

The answer of a script:

```json
{ "ok": true, "value": { "name": "Springfield" }, "console": [{ "level": "log", "text": "..." }] }
{ "ok": false, "error": "Error: No city is loaded.\n    at ...", "console": [] }
```

`value` is the value of the last expression as JSON. A value that JSON does not
have becomes a text; a `Map` becomes its entries; a `Set` and a typed array become
arrays. `console` holds the output of the script and the warnings and errors of the
game while the script ran. `timedOut` is true when the promise of the script did not
settle in time; the script continues in the game.

```sh
curl -s -X POST http://127.0.0.1:9240/eval -d 'tools.select("Roads", "Road"); tools.apply([30, 30], [40, 30])'
```

## Scripts of a request

A request runs as console input, with two differences:

- Its source runs in a block. `let`, `const` and `class` names end with the request,
  thus the next request can declare the same names. `var`, function declarations
  and the values of `globalThis` stay.
- It can run as long as its timeout, up to 60 seconds without a pause. A script
  that waits with `await` does not stop the game: the game draws, and other requests
  get their answers.

The default timeout is 30 seconds, and the longest is 10 minutes.

## Model Context Protocol

`/mcp` is an MCP server with the Streamable HTTP transport. Each POST holds one
JSON-RPC message and gets one JSON answer; the server sends no event stream. The
tools:

| Tool | Use |
| --- | --- |
| `eval` | Runs JavaScript: `{ source, timeout_ms }`. Returns the value as JSON text, then the console output. |
| `state` | Returns `game.state()`. |
| `city_data` | Returns the city as JSON: `{ x, y }` for one tile, `{ x, y, width, height }` for an area, nothing for the whole city. Also `{ fields, format, empty }`. |
| `screenshot` | Returns a PNG image of the game window: `{ scale }`. |
| `city_image` | Returns a PNG image of the city, or of some tiles: `{ x, y, width, height, size, view }`. |
| `control_image` | Returns a PNG picture of a control that draws its content: `{ target, scale }`. |
| `guide` | Returns the guide. `{ types: true }` adds the TypeScript declarations. |

Start the game, then add the server to the client. For Claude Code:

```sh
tools/remote_game.py start --window
claude mcp add --transport http opensc2k http://127.0.0.1:9240/mcp
```

The game must run before the client connects.

## What an agent can do

| Need | Functions |
| --- | --- |
| Know what the game shows | `game.state()`, `ui.windows()`, `ui.controls()`, `ui.texts()` |
| Read the report windows | `city.demographics`, `city.industry`, `city.neighbors`, `city.newspaper`, `budget.report`, `city.graph`, `city.dataMap` |
| Start, open and save cities | `game.newCity`, `game.open`, `game.saveAs`, `city.save`, `game.files` |
| Read the map without an image | `GET /city-data`, `city.cell`, `city.cells`, `city.textMap`, `city.query`, `city.find`, `city.census`, `city.signs` |
| Build | `tools.select`, `tools.apply`, `tools.undo` |
| Run the simulation | `sim.advance`, `sim.runTo`, `sim.speed`, `sim.suspended` |
| Budget, industry taxes and disasters | `budget.*`, `sim.startDisaster` |
| Answer windows and use menus | `ui.accept`, `ui.close`, `ui.press`, `ui.set`, `ui.choose`, `ui.menu`, `ui.chooseFile`, `game.action` |
| All other actions | `input.click`, `input.drag`, `input.key`, `input.text`, `input.scroll`, with `view.screenOf` |
| Images | `GET /city-image` and `city.exportPng` with an area of tiles, `GET /control-image` and `ui.image`, `ui.screenshot`, `GET /screenshot` |

[Scripting](scripting.md) describes each function. The `ui` functions use each
control as the player does: they change the control and send its signals. Thus the
game runs the same code as after a click. The `input` functions send mouse and key
events through the input of the engine. Each window of the game is reachable in
this way, also the Settings window, the Debug window and the SCURK editor, which
have no functions of their own.

Some controls draw their content: the charts of the Population, Industry and
Neighbors windows, the newspaper, the tables of the Debug window, and the canvas
and the palette of the SCURK editor. Such a control has no labels to read. It tells its content to `UiProbe`
with three optional functions:

| Function of the control | Scripts get it as |
| --- | --- |
| `probe_texts() -> PackedStringArray` | Lines of `ui.texts()`. |
| `probe_data() -> Dictionary` | `data` of the control in `ui.controls()`. A `Vector2` is a place in the control; scripts get it in pixels of the game window. |
| `probe_image() -> Image` | The picture of `ui.image` and `GET /control-image`. The control makes it without the screen. |

A control that code made without a name, and that has no text of its own, gets
`label`: the text of the label that the window shows before it. A tab or a row of
a tree that shows only an icon has its tooltip as its text.

Add these functions to a new control that draws text, takes a click on a drawn
part, or shows a picture that a script must see. `ui.menu` and `game.action` do
nothing while a modal window shows, as the menu bar and the keys of a player;
they throw an error that names the window.

A simulation prompt stops `sim.advance` and `sim.runTo`. Their answer has the
reason in `stopped`, and `game.state().windows` has the window:

```js
const run = await sim.advance(400); // { days: 300, date: {...}, stopped: 'prompt: annual budget' }
ui.accept(); // approves the yearly budget
```

## Headless and windowed games

| | Headless (`start`) | Windowed (`start --window`) |
| --- | --- | --- |
| A person can watch | No | Yes |
| `GET /screenshot`, `ui.screenshot` | No image | Yes |
| `GET /city-data`, `city.cell`, `city.cells`, `city.textMap` | Yes | Yes |
| `GET /city-image`, `city.exportPng` | Yes | Yes |
| `GET /control-image`, `ui.image` | Yes | Yes |
| `ui` and `input` functions | Yes | Yes |
| GPU renderer | No | Yes |

A headless game gets a window size of 1280 by 800 for its layout when the server
starts, thus each control has a place in whole pixels. `start --window` sets
`view.follow = true`: the view moves to each tile that `tools.apply` changes. A
headless run does not prove GPU pixel output.

An image of an area of tiles is the same part of the image of the whole city. The
game draws only the pixels of the area, thus the time and the size of the image do
not depend on the size of the map. The image holds each tile of the area and the
whole sprite of each structure that has a tile in the area. A map of 1024 tiles or
more is too large for one image at some tile sizes; an area of it is not.

The simulation runs in the same way in both. `sim.advance` runs days as fast as the
computer can; `sim.speed` and `sim.runTo` run in real time, as for a player.

## Safety

- The server is off until `--api` or the `api` command starts it.
- It listens on `127.0.0.1`. Other computers cannot connect.
- It refuses a request whose `Host` header does not name `127.0.0.1` or `localhost`,
  and each request with an `Origin` header. A web page in a browser on the same
  computer thus cannot use the port.
- Each program of the same computer can use the port while it is open. A script can
  save a city to each path that the game can write, and can close the game. Open the
  port only for tests and development.
- Mods cannot use the functions that control the interface, the input and the
  files; see [The sandbox](mods.md#the-sandbox).

## Code layout

| File | Contents |
| --- | --- |
| `game/src/application/remote_api.gd` | `ApplicationRemoteApi`: the routes, the scripts that wait for their value, the window image. |
| `game/src/application/automation/remote_http_server.gd`, `remote_http_request.gd` | The HTTP server on the main thread. |
| `game/src/application/automation/remote_mcp.gd` | The MCP route. |
| `game/src/application/automation/ui_probe.gd`, `ui_operator.gd`, `input_sender.gd` | Read the interface, use its controls, send input events. |
| `game/src/application/automation/city_text_map.gd` | The city as text. |
| `game/src/application/scripting_game_api.gd`, `scripting_ui_api.gd`, `scripting_input_api.gd` | The host functions of `game`, `ui` and `input`. |
| `game/src/application/scripting_reports_api.gd` | The host functions that give the values of the report windows and the newspaper. |
| `game/src/application/scripting_city_data_api.gd` | `city.cell` and `city.cells`: the city as data. |
| `native/core/scripting` | `Engine::eval_request` runs a request and sends its value as JSON to the host: `request(id, ok, json)`. |
| `tools/remote_game.py` | The shell client. |

The tests are `remote_api_test`, `ui_automation_test` and `ui_automation_test_native`
in the `scripting` validation domain.
