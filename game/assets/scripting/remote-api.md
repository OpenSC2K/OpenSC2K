# Play OpenSC2K through the remote API

OpenSC2K is an open-source remake of SimCity 2000. You control it with JavaScript.
Each request runs one script in the game and returns the value of its last expression
as JSON.

## Send a script

| Client | Call |
| --- | --- |
| HTTP | `POST /eval` with the source as the body. The answer is `{ ok, value, error, console }`. |
| MCP | The `eval` tool with `{ source }`. |
| Shell | `tools/remote_game.py eval 'city.info()'`, or `eval -` with the source on standard input. |

- `console` holds the console output of the script, also the errors of the game.
- `let`, `const` and `class` names end with the request. Use the same names again in
  the next request. `var`, function declarations and `globalThis` values stay.
- Top-level `await` is permitted. The answer waits for the promise, for 30 seconds
  by default. `POST /eval?timeout=120000` waits longer.
- A function that cannot do its work throws an Error with the reason.
- `GET /types` returns the TypeScript declarations of every function. Read them when
  you need a function that this guide does not show.

## The loop

1. Do an action.
2. Read `game.state()`. `status` is the result or the error of the last action.
   `windows` lists the windows that show. `suspended` tells why the simulation waits.
3. When a window waits for an answer, answer it: `ui.accept()`, `ui.close()` or
   `ui.press('Button text')`.

```js
game.state();
// { screen: 'city', status: 'Built 11 Road tiles for $110.', suspended: '',
//   city: { name, funds, population, date, demand, path, ... },
//   speed, tool, view, disaster, windows: [{ id, type, title, text, blocking, buttons }] }
```

`screen` is `main-menu`, `new-city`, `terrain-editor`, `city`, `scurk` or `startup`.

## Start a game

```js
game.newCity({ name: 'Springfield', difficulty: 'easy', year: 1900, size: 128, seed: 7 });
ui.close(); // the founding newspaper waits for a close
game.files(); // { cities, scenarios, saved, savedFolder }: files that game.open takes
game.open('/full/path/CITY.SC2', { discard: true }); // discard drops unsaved changes
await game.saveAs('/full/path/my-city.sc2x');
city.save(); // to the file of the city
city.unsaved; // true when the city has changes that its file does not have
```

`newCity` also takes `mayor`, `sc2` (true makes an SC2 file that the original game
opens), `ocean`, `river`, `hills`, `water`, `trees` (0 to 47), `features` and `edit`
(true stays in the terrain editor).

## Read the city

```js
city.info(); // name, funds, population, date, demand
city.textMap({ x: 40, y: 40, width: 40, height: 20 }); // { rows, legend }: one character for each tile
city.textMap(undefined, 'zones'); // the whole map; layers: surface, zones, underground, altitude, power, water
city.tile(64, 64); // the stored values, the structure name, the zone name
city.query(64, 64); // what the Query tool shows
city.census(); // tiles of each structure and zone, powered and unpowered tiles
city.find('Police Station'); // [{ x, y, name }]
city.region(40, 40, 20, 20); // arrays of stored values for your own analysis
city.dataMap('pollution'); city.graph('Residents');
budget.info(); budget.ordinances(); city.demand;
city.demographics(); // the Population window: residents, life expectancy and education of each age group
city.industry(); // the Industry window: [{ key, name, ratio, taxRate, demand }]
city.neighbors(); // the Neighbors window: the neighbor cities and the national population
budget.report(); // the Budget window: the amount of each line, the totals, the bonds
```

Character `i` of `rows[j]` is the tile `(x + i, y + j)`. Tile coordinates go from 0 to
`city.size - 1`. On the surface layer, `.` is clear land, `/` a slope, `~` water, `t`
trees, `=` road, `#` rail, `+` a power line, lower case `r c i` an empty zone, upper
case `R C I` a building, `P` a power plant. The `legend` of the answer names each
character.

## Build

```js
tools.list(); // every tool: { groupName, name, cost, available }
tools.select('Roads', 'Road');
tools.apply([30, 30], [40, 30]); // a drag from one tile to another: { changed, cost, message }
tools.select('Residential', 'Dense Residential');
tools.apply([30, 31], [40, 33]); // a zone fills the rectangle
tools.select('Power', 'Coal Power Plant');
tools.apply([44, 31]); // one click
tools.select('Bulldozer', 'Demolish'); tools.apply([30, 30]);
tools.undo();
```

- `changed` false means that nothing was built. `message` tells why.
- A tool that needs a choice opens a window: a bridge, a tunnel, a connection to a
  neighbor, the team of a stadium. Find it in `game.state().windows` and answer it.
- A zone grows only beside a tile that has power. Connect each zone block to a power
  plant with power lines. Zones need a road, a rail line or a highway within three tiles.
- Residents come when the city has jobs: give power to the industrial zones first.

## Run the simulation

```js
await sim.advance(30); // pauses, then runs 30 days fast: { days, date, stopped }
await sim.runTo({ year: 1905, month: 1, day: 1 }); // runs at Cheetah speed to a date: { date, stopped }
sim.speed = 'Llama'; sim.pause(); sim.resume(); // real time, for a person who watches
sim.suspended; // '' or the reason: 'prompt: annual budget', 'window: ...', 'newspaper', 'game over'
```

`advance` and `runTo` stop early when the simulation must wait. `stopped` gives the
reason. Answer the window, then continue. While a disaster is active, the game runs
the ticks of the disaster and no days: `advance` then stops with `'disaster: Fire'`.
Fight the disaster with the Dispatch tools and call `advance` again, or end it with
the cheat `sim.endDisaster()`. The yearly budget window opens each January:
`ui.accept()` approves it. `budget.set({ autoBudget: true })` turns the yearly window off.

```js
budget.set({ taxes: { residential: 8 }, funding: { police: 90 } });
budget.set({ industryTaxes: { all: 3, textiles: 7 } }); // the tax rate of each industry, 0 to 20
budget.setOrdinance('proReading', true);
budget.issueBond();
sim.startDisaster('Fire', 64, 64); sim.noDisasters = true; city.funds = 50000; // cheats
```

## Windows, menus and dialogs

Use these for each action that has no function of its own.

```js
ui.windows(); // the lowest first; the last takes the input: { id, type, title, text, modal, blocking, buttons }
ui.controls(); // the controls of the top window: { id, kind, name, text, value, disabled, items, rect }
ui.texts(); // the texts that the top window shows
ui.press('OK'); // a button by its text, its node name or its id
ui.set('CityNameInput', 'Springfield'); // a text field, a number, a check box
ui.choose('Tabs', 'Bonds'); // an option, a tab, a row of a list or a tree
ui.accept(); ui.close(); // the OK button, or the close button, of the top window
ui.menus(); ui.menu('Windows', 'Graphs'); // the menu bar
ui.chooseFile('/full/path/file.sc2'); // answers the file dialog that shows
game.actions(); game.action('window_budget'); // the actions of the keys
```

- `ui.controls('main')` lists the controls of the game window: the toolbar and the menu bar.
- When more than one control has the same text, the error lists their ids. Use an id.
- A control under a modal window cannot be used. Answer the modal window first. `ui.menu`
  and `game.action` also throw while a modal window shows.
- `ui.texts()` also gives the texts that a window draws: the charts and the newspaper.

The newspaper opens by itself (`suspended` is then `'newspaper'`), or from its menu:

```js
ui.menu('Newspaper', city.newspapers[0]);
city.newspaper(); // { title, date, price, stories: [{ headline, article }], weather, opinion, extra }
ui.close();
```

## Mouse, keys and images

```js
const place = view.screenOf(64, 64); // a tile -> pixels of the game window
input.click(place.x, place.y); // uses the selected tool on the tile, as a mouse click does
await input.drag([400, 300], [520, 360]);
input.key('Ctrl+S'); input.text('hello'); input.scroll(3, 640, 400);
view.centerOn(64, 64); view.zoomIn(); view.rotate(); view.mode = 'pollution';
await ui.screenshot('/full/path/screen.png'); // needs a game with a window
await city.exportPng('/full/path/part.png', { area: { x: 40, y: 40, width: 12, height: 12 }, size: 'large' });
await city.exportPng('/full/path/city.png'); // the whole city: a large image
```

- **An image of some tiles:** `GET /city-image?x=40&y=40&width=12&height=12&size=large`
  and the MCP `city_image` tool return a PNG of only those tiles. `city.exportPng` with
  `area` writes the same image to a file. These work in a headless game. The game draws
  only the area, thus a small area is fast on a map of each size. Prefer this to an
  image of the whole city, which can be too large to read.
- **The size of the tiles:** `size` is `small` (a tile is 8 pixels wide, the default),
  `medium` (16) or `large` (32). An area of 12 by 12 tiles at `large` is about 400 by
  250 pixels. `view: 'underground'` draws the pipes and the subways.
- **The window:** `GET /screenshot` and the MCP `screenshot` tool return the image of
  the window. A headless game has no window image. A position of `input` and each
  `rect` are in pixels of the full-size window image.
- **A control that draws its content:** `GET /control-image?target=PixelCanvas&scale=4`,
  the MCP `control_image` tool and `ui.image(target, path, { scale })` return its
  picture. These work in a headless game. `ui.controls()` marks such a control with
  `image: true`.

## The SCURK editor

`ui.press('SCURK')` on the main menu opens the tile editor. It has no functions of its
own: use its buttons and menus with `ui`, and draw with `input`. Its two drawn controls
give `data` to find a place:

```js
const find = (name) => ui.controls().find((control) => control.name === name);
const colors = find('Colors').data; // { columns, selected, indices, colors: ['#rrggbb'], origin, end }
const canvas = find('PixelCanvas').data; // { spriteWidth, spriteHeight, zoom, tool, colorIndex, editable, origin, end }
const cell = (colors.end.x - colors.origin.x) / colors.columns;
input.click(colors.origin.x + (40 % 16 + 0.5) * cell, colors.origin.y + (Math.floor(40 / 16) + 0.5) * cell); // palette cell 40
const size = (canvas.end.x - canvas.origin.x) / canvas.spriteWidth;
const at = (x, y) => [canvas.origin.x + (x + 0.5) * size, canvas.origin.y + (y + 0.5) * size];
await input.drag(at(50, 244), at(78, 244)); // a line on the sprite
ui.image('PixelCanvas', '/full/path/tile.png', { scale: 4 }); // look at the result
```

`origin` and `end` are the corners of the cells or of the sprite, in pixels of the window.

## Other functions

- `game.mainMenu()`, `game.quit({ discard: true })`, `game.debugMode = true`.
- `game.preferences` gives the settings in use. Change a setting in the Settings window:
  `game.action('settings')`, then `ui.choose('Tabs', 'Audio')` and `ui.set`.
- `game.wait(ms)`, `game.frames(count)`, `await game.until(() => !sim.suspended)`.
- `game.on(type, listener)` listens to game events; `game.events` lists them.
- `view.follow = true` moves the view to each tile that `tools.apply` changes.
- The Settings window and the Debug window have no functions of their own. Use the `ui`
  and `input` functions for them.
