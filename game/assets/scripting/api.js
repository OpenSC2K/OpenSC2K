// The OpenSC2K game API of scripts. The game runs this file after the core
// of the runtime (native/core/scripting/src/prelude.js). Each function calls a
// GDScript host function of ApplicationScriptingApi. See docs/scripting.md.
(function (global) {
  'use strict';

  const { host, events, command } = global.__runtime;

  // the file functions of a mod; only the runtime of a mod has them
  const nativeFiles = global.__files;
  delete global.__files;

  // a tile point from (x, y), ({ x, y }) or ([x, y])
  function point(x, y) {
    if (Array.isArray(x)) {
      return { x: x[0], y: x[1] };
    }

    if (x !== null && typeof x === 'object') {
      return { x: x.x, y: x.y };
    }

    return { x, y };
  }

  // a position in the game window from (x, y), ({ x, y }) or ([x, y]); null without one
  function place(x, y) {
    return x === undefined || x === null ? null : point(x, y);
  }

  // an area of tiles from (x, y, width, height), ({ x, y, width, height }) or nothing: the whole map
  function area(x, y, width, height) {
    if (x === undefined || x === null) {
      return null;
    }

    return typeof x === 'object' ? { x: x.x, y: x.y, width: x.width, height: x.height } : { x, y, width, height };
  }

  // promises that the game settles when its work ends, such as an image of
  // the window. `start(token)` begins the work
  const waits = new Map();
  let nextWait = 1;

  function wait(start) {
    return new Promise((resolve, reject) => {
      const token = nextWait++;
      waits.set(token, { resolve, reject });

      try {
        start(token);
      } catch (error) {
        waits.delete(token);
        reject(error);
      }
    });
  }

  Object.defineProperty(global, '__gameApi', {
    value: Object.freeze({
      settle(token, ok, value) {
        const waiting = waits.get(token);

        if (!waiting) {
          return;
        }

        waits.delete(token);

        if (ok) {
          waiting.resolve(value);
        } else {
          waiting.reject(new Error(String(value)));
        }
      },
    }),
    configurable: false,
    enumerable: false,
    writable: false,
  });

  // resolves after the game drew this many frames
  function frames(count = 1) {
    return new Promise((resolve) => {
      let left = Math.max(1, Math.floor(count));

      const stop = events.on('frame', () => {
        left -= 1;

        if (left <= 0) {
          stop();
          resolve();
        }
      });
    });
  }

  // resolves when `test()` is true, or rejects after the timeout in milliseconds
  async function until(test, timeout = 30000) {
    const end = Date.now() + timeout;

    while (!test()) {
      if (Date.now() >= end) {
        throw new Error(`The condition was not true after ${timeout} ms`);
      }

      await frames(1);
    }
  }

  const game = Object.freeze({
    get version() {
      return host('game.version');
    },

    // the events of the game: { name: description }
    get events() {
      return host('game.events');
    },

    // the info of each mod that runs: [{ id, name, version, ... }]
    get mods() {
      return host('game.mods');
    },

    on: events.on,
    once: events.once,
    off: events.off,
    listenerCount: events.listenerCount,

    // sends an event to the script listeners of the console and of each mod,
    // with a copy of the detail. The game does not see it
    emit: events.emit,

    // adds a console command: command(name, description, (...words) => text)
    command,

    // shows a message on the status bar
    status(text) {
      host('game.status', String(text));
    },

    // what the game shows now: { screen, city, speed, suspended, tool, view, windows, status, ... }
    state() {
      return host('game.state');
    },

    // the actions of the keys and menus: [{ id, label, category, scope, kind }]
    actions() {
      return host('game.actions');
    },

    // runs an action as its key does: action('window_budget'). False when it does nothing now
    action(id) {
      return host('game.action', String(id));
    },

    // makes the terrain and founds a city: newCity({ name: 'Springfield', size: 128, seed: 7 })
    newCity(options = {}) {
      return host('game.newCity', options);
    },

    // opens a city or a scenario file: open('/path/city.sc2', { discard: true })
    open(path, options = {}) {
      return host('game.open', String(path), options);
    },

    // saves the city to a path, and resolves with the path when the file is written
    async saveAs(path) {
      host('game.saveAs', String(path));
      await until(() => !host('game.busy'), 600000);
      const saved = host('city.info').path;

      if (!saved || saved.split(/[\\/]/).pop() !== String(path).split(/[\\/]/).pop()) {
        throw new Error(`The city was not saved to ${path}`);
      }

      return saved;
    },

    // what the game plays now: { music: { enabled, playing, paused, track, name }, sound: { enabled, loop } }
    audio() {
      return host('game.audio');
    },

    // the city files that the game knows: { cities, scenarios, saved, savedFolder, autosaves }
    files() {
      return host('game.files');
    },

    // shows the main menu, or with false returns from it to the city
    mainMenu(show = true) {
      return host('game.mainMenu', Boolean(show));
    },

    // closes the game: quit({ discard: true }) drops unsaved changes
    quit(options = {}) {
      return host('game.quit', options);
    },

    // the stored settings: { section: { key: value } }
    get settings() {
      return host('game.settings');
    },

    // the settings that the game uses now: { defaultMayorName, musicVolume, ... }.
    // the Settings window changes them
    get preferences() {
      return host('game.preferences');
    },

    // the debug mode: the Debug menu and the debug tools
    get debugMode() {
      return host('game.debugMode', null);
    },

    set debugMode(value) {
      host('game.debugMode', Boolean(value));
    },

    // resolves after a time in milliseconds
    wait(milliseconds) {
      return new Promise((resolve) => setTimeout(resolve, milliseconds));
    },

    // resolves after the game drew this many frames
    frames,

    // resolves when test() is true: await game.until(() => !sim.suspended)
    until,

    // values that stay after the game closes. Each value must be JSON data.
    // Each mod has its own values, in storage.json in its folder
    storage: Object.freeze({
      get: (key, fallback) => host('storage.get', String(key), fallback === undefined ? null : fallback),
      set: (key, value) => host('storage.set', String(key), value),
      remove: (key) => host('storage.remove', String(key)),
      keys: () => host('storage.keys'),
    }),
  });

  const city = Object.freeze({
    get loaded() {
      return host('city.loaded');
    },

    // a copy of the main city values
    info() {
      return host('city.info');
    },

    get name() {
      return host('city.info').name;
    },

    get mayor() {
      return host('city.info').mayor;
    },

    // the number of tiles on each map edge
    get size() {
      return host('city.info').size;
    },

    get population() {
      return host('city.info').population;
    },

    get date() {
      return host('city.info').date;
    },

    get demand() {
      return host('city.info').demand;
    },

    get funds() {
      return host('city.info').funds;
    },

    set funds(value) {
      host('city.setFunds', value);
    },

    addFunds(amount) {
      return host('city.addFunds', amount);
    },

    // the stored values of one tile, or null outside the map
    tile(x, y) {
      return host('city.tile', point(x, y));
    },

    // the value of a data map at a tile, such as city.data('pollution', 10, 20)
    data(name, x, y) {
      return host('city.data', name, point(x, y));
    },

    // a whole data map: { name, size, scale, values, at(x, y) }
    dataMap(name) {
      const map = host('city.dataMap', name);

      map.at = (x, y) => {
        const tile = point(x, y);

        return map.values[Math.floor(tile.x / map.scale) * map.size + Math.floor(tile.y / map.scale)];
      };

      return map;
    },

    get dataMaps() {
      return host('city.dataMaps');
    },

    // a graph history, oldest value first: graph('Residents', 'decade')
    graph(name, period = 'year') {
      return host('city.graph', name, period);
    },

    get graphs() {
      return host('city.graphs');
    },

    rename(name) {
      return host('city.rename', String(name));
    },

    // the text of the sign on a tile, or null
    sign(x, y) {
      return host('city.sign', point(x, y));
    },

    // places or changes a sign; an empty text removes it
    // every sign of the city: [{ x, y, text }]
    signs() {
      return host('city.signs');
    },

    setSign(x, y, text) {
      return host('city.setSign', point(x, y), String(text));
    },

    // the moving objects: { id, type, name, x, y, state }
    things() {
      return host('city.things');
    },

    // saves the city to its file
    save() {
      return host('city.save');
    },

    // true when the city has changes that its file does not have. It compares the whole city
    get unsaved() {
      return host('city.unsaved');
    },

    // what the Query tool shows for a tile: { title, text, zone, landValue, crime, ... }
    query(x, y) {
      return host('city.query', point(x, y));
    },

    // the stored values of an area: { x, y, width, height, building, zone, terrain,
    // underground, altitude, water, powered, watered }. Tile (x + i, y + j) is at j * width + i
    region(x, y, width, height) {
      return host('city.region', area(x, y, width, height));
    },

    // an area as text, one character for each tile: { rows, legend, ... }.
    // textMap({ x: 40, y: 40, width: 40, height: 20 }, 'zones')
    textMap(where, layer = 'surface') {
      return host('city.textMap', where === undefined ? null : area(where), layer);
    },

    get textLayers() {
      return host('city.textLayers');
    },

    // the tiles of a structure by name or stored id: find('Police Station')
    find(what, where) {
      return host('city.find', what, where === undefined ? null : area(where));
    },

    // the number of tiles of each structure and zone: { structures, zones, water, powered, unpowered }
    census(where) {
      return host('city.census', where === undefined ? null : area(where));
    },

    // each value of one tile, and what the Query tool tells about it:
    // { x, y, altitude, slope, water, structure, zone, density, underground, powered, ..., query }
    cell(x, y) {
      return host('city.cell', point(x, y));
    },

    // the values of each tile of an area, or of the whole map without an area:
    // cells({ x: 40, y: 40, width: 8, height: 8 }, { fields: ['structure', 'zone'], format: 'cells' })
    cells(where, options = {}) {
      return host('city.cells', where === undefined || where === null ? null : area(where), options);
    },

    // the names of the values of a cell
    get cellFields() {
      return host('city.cellFields');
    },

    // the values of the Population window: { population, workforcePercent,
    // workforceLifeExpectancy, workforceEducation, ages: [{ age, population, lifeExpectancy, education }] }
    demographics() {
      return host('city.demographics');
    },

    // the values of the Industry window: [{ key, name, ratio, taxRate, demand }]
    industry() {
      return host('city.industry');
    },

    // the values of the Neighbors window: { name, population, nationalPopulation, neighbors: [{ name, population, edge }] }
    neighbors() {
      return host('city.neighbors');
    },

    // the names of the papers of the Newspaper menu
    get newspapers() {
      return host('city.newspapers');
    },

    // the paper that shows: { title, date, price, stories: [{ headline, article }], weather, opinion, extra }.
    // null when no paper shows. ui.menu('Newspaper', city.newspapers[0]) opens a paper
    newspaper() {
      return host('city.newspaper');
    },

    // writes an image of the city to a PNG file: exportPng('/tmp/city.png', { size: 'small' }).
    // with an area, the image shows only those tiles: { area: { x: 40, y: 40, width: 12, height: 12 } }
    async exportPng(path, options = {}) {
      host('city.exportPng', String(path), options);
      await until(() => !host('city.exporting'), 600000);

      return host('city.exported');
    },
  });

  const budget = Object.freeze({
    // { taxes, funding, industryTaxes, autoBudget, bonds }
    info() {
      return host('budget.info');
    },

    // the amounts of the Budget window: { year, yearEnd, recordedMonths, funds, yearToDate, estimate,
    // yearEndFunds, lines: [{ key, name, group, rate, yearToDate, estimate, months }], bonds }
    report() {
      return host('budget.report');
    },

    get industryTaxes() {
      return host('budget.info').industryTaxes;
    },

    get taxes() {
      return host('budget.info').taxes;
    },

    get funding() {
      return host('budget.info').funding;
    },

    // set({ taxes: { residential: 8 }, funding: { police: 90 }, industryTaxes: { textiles: 5 }, autoBudget: true })
    set(changes) {
      return host('budget.set', changes);
    },

    // every ordinance: { key, name, category, enabled, cost }
    ordinances() {
      return host('budget.ordinances');
    },

    setOrdinance(key, enabled = true) {
      return host('budget.setOrdinance', String(key), Boolean(enabled));
    },

    issueBond() {
      return host('budget.issueBond');
    },

    repayBond() {
      return host('budget.repayBond');
    },
  });

  const ui = Object.freeze({
    // a message window with an OK button
    alert(text, title = 'Script') {
      host('ui.alert', String(text), String(title));
    },

    status(text) {
      host('game.status', String(text));
    },

    // plays SOUNDS/<id>.WAV of the sound pack
    playSound(id) {
      host('ui.playSound', id);
    },

    // the windows that show, the lowest first: [{ id, type, title, text, modal, blocking, buttons, rect }]
    windows() {
      return host('ui.windows');
    },

    // the controls of a window that take input: [{ id, kind, type, name, text, value, disabled, rect, items }]
    controls(window) {
      return host('ui.controls', window === undefined ? null : window);
    },

    // the texts that a window shows, top to bottom
    texts(window) {
      return host('ui.texts', window === undefined ? null : window);
    },

    // presses a button by its id or its text: press('OK')
    press(target) {
      return host('ui.press', target);
    },

    // sets a text field, a number or a check box: set('CityNameInput', 'Springfield')
    set(target, value, options = {}) {
      return host('ui.set', target, value, Boolean(options.submit));
    },

    // chooses an item by text or index: an option, a tab, a list or tree row, a menu item
    choose(target, item, options = {}) {
      return host('ui.choose', target, item, Boolean(options.activate));
    },

    // the menus of the menu bar with their items
    menus() {
      return host('ui.menus');
    },

    // chooses an item of the menu bar: menu('File', 'Save City')
    menu(...path) {
      return host('ui.menu', path.flat());
    },

    // answers a dialog with its OK button. Without a window: the top one
    accept(window) {
      return host('ui.accept', window === undefined ? null : window);
    },

    // closes a window as its close button does; a dialog takes it as Cancel
    close(window) {
      return host('ui.close', window === undefined ? null : window);
    },

    // selects a path in the file dialog that shows
    chooseFile(path) {
      return host('ui.chooseFile', String(path));
    },

    // the size of the game window in pixels: { width, height, headless }
    get screen() {
      return host('ui.screen');
    },

    // saves an image of the game window: resolves with { path, width, height }
    screenshot(path, options = {}) {
      const file = path === undefined ? null : String(path);

      return wait((token) => host('ui.screenshot', token, file, options.scale || 1));
    },

    // saves the picture of a control that draws its content, such as the canvas of the
    // SCURK editor: image('PixelCanvas', '/tmp/tile.png', { scale: 8 }). A headless game can do this.
    // without a target, the first such control of the top window is used: { path, width, height }
    image(target, path, options = {}) {
      return host('ui.image', target === undefined ? null : target, String(path), options.scale || 1);
    },
  });

  // mouse and keyboard input, as the devices of the player send it. A
  // position is in pixels of the game window
  const input = Object.freeze({
    // the place of the pointer of scripts
    get position() {
      return host('input.position');
    },

    move(x, y) {
      return host('input.move', place(x, y));
    },

    mouseDown(x, y, button = 'left') {
      return host('input.button', button, true, place(x, y), false);
    },

    mouseUp(x, y, button = 'left') {
      return host('input.button', button, false, place(x, y), false);
    },

    // a click at a place: click(640, 400), click(640, 400, { button: 'right' })
    click(x, y, options = {}) {
      const button = options.button || 'left';
      host('input.button', button, true, place(x, y), Boolean(options.double));

      return host('input.button', button, false, null, false);
    },

    // a drag from one place to another, one step each frame
    async drag(from, to, options = {}) {
      const start = point(from);
      const end = point(to);
      const button = options.button || 'left';
      const steps = Math.max(1, options.steps || 8);
      host('input.button', button, true, start, false);

      for (let step = 1; step <= steps; step++) {
        await frames(1);
        host('input.move', {
          x: start.x + ((end.x - start.x) * step) / steps,
          y: start.y + ((end.y - start.y) * step) / steps,
        });
      }

      await frames(1);

      return host('input.button', button, false, end, false);
    },

    // turns the mouse wheel; a positive step scrolls down
    scroll(steps = 1, x, y, options = {}) {
      return host('input.scroll', steps, place(x, y), Boolean(options.horizontal));
    },

    // presses and releases a key: key('Ctrl+S'), key('Escape'), key('F12')
    key(text) {
      host('input.key', String(text), true);

      return host('input.key', String(text), false);
    },

    keyDown(text) {
      return host('input.key', String(text), true);
    },

    keyUp(text) {
      return host('input.key', String(text), false);
    },

    // types a text into the control with the focus
    text(value) {
      return host('input.text', String(value));
    },

    // releases every mouse button and modifier key that a script holds
    release() {
      return host('input.release');
    },
  });

  const sim = Object.freeze({
    // 'Paused', 'Turtle', 'Llama', 'Cheetah' or 'African Swallow'
    get speed() {
      return host('sim.speed');
    },

    set speed(value) {
      host('sim.setSpeed', value);
    },

    get paused() {
      return host('sim.speed') === 'Paused';
    },

    pause() {
      host('sim.setSpeed', 'Paused');
    },

    // selects the speed before the pause
    resume() {
      host('sim.resume');
    },

    // runs one day while the game is paused. Returns a report
    step() {
      return host('sim.step');
    },

    // the active disaster { id, name }, or null
    get disaster() {
      return host('sim.disaster');
    },

    // the disasters { name: id } that startDisaster takes
    get disasters() {
      return host('sim.disasters');
    },

    // starts a disaster by name or id, at a tile or at the view center
    startDisaster(disaster, x, y) {
      return host('sim.startDisaster', disaster, x === undefined ? null : point(x, y));
    },

    // ends the active disaster and clears its marks. False without a disaster
    endDisaster() {
      return host('sim.endDisaster');
    },

    // true when random disasters are off
    get noDisasters() {
      return host('sim.noDisasters');
    },

    set noDisasters(value) {
      host('sim.setNoDisasters', Boolean(value));
    },

    // runs at the speed until the date, then pauses: runUntil({ year: 2051, month: 1, day: 1 })
    runUntil(date, speed = 'Cheetah') {
      const speeds = { Turtle: 2, Llama: 3, Cheetah: 4, 'African Swallow': 5 };

      return host('sim.runUntil', date, typeof speed === 'number' ? speed : speeds[speed] || 4);
    },

    // why the simulation waits now, or '': a prompt, a window that blocks it, the terrain editor
    get suspended() {
      return host('sim.suspended');
    },

    // pauses the game and runs this many days, as fast as the computer can.
    // It stops early when the simulation must wait: { days, date, stopped }
    async advance(days = 1) {
      host('sim.setSpeed', 'Paused');
      const start = host('city.info').date.age;
      let age = start;
      let sliceStart = Date.now();
      // the steps in a row that ended no day: a step is one tick of an active disaster
      let ticks = 0;

      while (age < start + days && ticks < 32 && !host('sim.suspended')) {
        host('sim.step');
        const now = host('city.info').date.age;
        ticks = now === age ? ticks + 1 : 0;
        age = now;

        // let the game draw and answer other requests
        if (Date.now() - sliceStart > 40) {
          await frames(1);
          sliceStart = Date.now();
        }
      }

      const disaster = host('sim.disaster');
      const waits = host('sim.suspended');

      return {
        days: age - start,
        date: host('city.info').date,
        stopped: waits || (age < start + days && disaster ? `disaster: ${disaster.name}` : ''),
      };
    },

    // runs at the speed until the date and resolves when the game paused
    // there, or when the simulation must wait: { date, stopped }
    async runTo(date, speed = 'Cheetah') {
      sim.runUntil(date, speed);

      do {
        await frames(1);

        if (host('sim.suspended')) {
          break;
        }
      } while (host('sim.speed') !== 'Paused');

      return { date: host('city.info').date, stopped: host('sim.suspended') };
    },
  });

  const tools = Object.freeze({
    // every tool: { group, subtool, groupName, name, cost }
    list() {
      return host('tools.list');
    },

    get selected() {
      return host('tools.selected');
    },

    // select('Roads', 'Road'), select('Road'), or select(group, subtool)
    select(group, subtool) {
      return host('tools.select', group, subtool === undefined ? null : subtool);
    },

    // uses the selected tool from one tile to another, as a drag does.
    // Stretch Terrain takes the height of its drag: apply([x, y], null, { levels: 2 })
    apply(from, to, options = {}) {
      const start = point(from);

      return host('tools.apply', start, to === undefined || to === null ? start : point(to), options);
    },

    undo() {
      return host('tools.undo');
    },
  });

  const view = Object.freeze({
    get center() {
      return host('view.center');
    },

    centerOn(x, y) {
      return host('view.centerOn', point(x, y));
    },

    // 'city', 'underground', 'traffic', 'pollution', ...
    get mode() {
      return host('view.mode');
    },

    set mode(value) {
      host('view.setMode', value);
    },

    get modes() {
      return host('view.modes');
    },

    // the zoom in percent
    get zoom() {
      return host('view.zoom');
    },

    zoomIn() {
      return host('view.zoomIn');
    },

    zoomOut() {
      return host('view.zoomOut');
    },

    // the compass rotation of the map, 0 to 3
    get rotation() {
      return host('view.rotation');
    },

    // a quarter turn, clockwise unless the argument is false
    rotate(clockwise = true) {
      return host('view.rotate', Boolean(clockwise));
    },

    // true moves the view to each tile that a script uses a tool on, for a person who watches
    get follow() {
      return host('view.follow');
    },

    set follow(value) {
      host('view.setFollow', Boolean(value));
    },

    // the center of a tile in pixels of the game window: { x, y, visible }
    screenOf(x, y) {
      return host('view.screenOf', point(x, y));
    },

    // the tile at a place of the game window, or null outside the map
    tileAt(x, y) {
      return host('view.tileAt', point(x, y));
    },

    // the layers that show: { buildings, networks, water, trees, signs, vehicles, ... }
    get layers() {
      return host('view.layers');
    },

    // shows or hides a layer, as the View menu does
    setLayer(name, shown = true) {
      return host('view.setLayer', String(name), Boolean(shown));
    },
  });

  // the bytes of a Uint8Array, another typed array, a DataView, an ArrayBuffer or an array of numbers
  function bytes(data) {
    if (data instanceof Uint8Array) {
      return data;
    }

    if (data instanceof ArrayBuffer) {
      return new Uint8Array(data);
    }

    if (ArrayBuffer.isView(data)) {
      return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
    }

    if (Array.isArray(data)) {
      return Uint8Array.from(data);
    }

    throw new TypeError('The data must be a Uint8Array, an ArrayBuffer, a typed array or an array of bytes');
  }

  // the files of the mod folder. Each path is relative to the folder; a path
  // outside it throws an Error
  function modFiles(native) {
    return Object.freeze({
      readText: (path) => native.readText(String(path)),
      readBytes: (path) => native.readBytes(String(path)),
      readJSON: (path) => JSON.parse(native.readText(String(path))),
      writeText: (path, text) => native.write(String(path), String(text), false),
      appendText: (path, text) => native.write(String(path), String(text), true),
      writeBytes: (path, data) => native.write(String(path), bytes(data), false),
      writeJSON: (path, value, space = 2) => native.write(String(path), JSON.stringify(value, null, space), false),
      exists: (path) => native.exists(String(path)),
      stat: (path) => native.stat(String(path)),
      list: (path = '.') => native.list(String(path)),
      makeFolder: (path) => native.makeFolder(String(path)),
      remove: (path, options) => native.remove(String(path), Boolean(options && options.recursive)),
      rename: (from, to) => native.rename(String(from), String(to)),
    });
  }

  const globals = { game, city, budget, sim, tools, view, ui, input };
  const info = nativeFiles ? host('mod.info') : null;

  if (info) {
    globals.mod = Object.freeze({
      id: info.id,
      name: info.name,
      version: info.version,
      // all fields of info.json
      info: Object.freeze(info),
      files: modFiles(nativeFiles),
    });
  }

  const fixed = { configurable: true, enumerable: true, writable: false };

  for (const [name, value] of Object.entries(globals)) {
    Object.defineProperty(global, name, { value, ...fixed });
  }
})(globalThis);
