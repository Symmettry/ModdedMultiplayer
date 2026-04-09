process.on('uncaughtException', (err) => {
  console.error('UNCAUGHT EXCEPTION');
  console.error(err);
});

process.on('unhandledRejection', (err) => {
  console.error('UNHANDLED REJECTION');
  console.error(err);
});

const axios = require('axios');
const readlineSync = require('readline-sync');

const BASE_URL = process.env.BASE_URL || 'http://127.0.0.1:3001';
const PLAYER_NAME = process.env.PLAYER_NAME || 'Test Client';

const state = {
  playerId: null,
  playerToken: null,
  partyCode: null,
  party: null,
  lastEventId: 0,
  running: true,
};

const MATCH_STATES = {
  LOBBY: 'LOBBY',
  RUNNING_TO_BOSS: 'RUNNING_TO_BOSS',
  WAITING_AT_BOSS: 'WAITING_AT_BOSS',
  BOSS_COUNTDOWN: 'BOSS_COUNTDOWN',
  BOSS_ACTIVE: 'BOSS_ACTIVE',
  BOSS_RESOLVED: 'BOSS_RESOLVED',
  MATCH_COMPLETE: 'MATCH_COMPLETE',
};

function hasSession() {
  return Boolean(state.partyCode && state.playerId && state.playerToken);
}

function getMyPlayer() {
  if (!state.party || !Array.isArray(state.party.players)) return null;
  return state.party.players.find((p) => p.playerId === state.playerId) || null;
}

function isHost() {
  const me = getMyPlayer();
  return Boolean(me && me.isHost);
}

function printDivider() {
  console.log('------------------------------------------------------------');
}

function printError(error) {
  console.error('Error:', error);
}

function authBody(extra = {}) {
  return {
    partyCode: state.partyCode,
    playerId: state.playerId,
    playerToken: state.playerToken,
    ...extra,
  };
}

async function post(path, body) {
  const res = await axios.post(`${BASE_URL}${path}`, body, {
    headers: { 'Content-Type': 'application/json' },
    timeout: 10000,
  });
  return res.data;
}

async function get(path) {
  const res = await axios.get(`${BASE_URL}${path}`, {
    timeout: 10000,
  });
  return res.data;
}

function updatePartyFromResponse(data) {
  if (data && data.party) {
    state.party = data.party;
    if (typeof data.party.lastEventId === 'number') {
      state.lastEventId = Math.max(state.lastEventId, data.party.lastEventId);
    }
  }
}

function printPartySummary() {
  printDivider();
  if (!state.party) {
    console.log('No active party loaded.');
    printDivider();
    return;
  }

  console.log(`Party: ${state.party.partyCode}`);
  console.log(`State: ${state.party.state}`);
  console.log(`Match ID: ${state.party.matchId || '(none)'}`);
  console.log(`Seed: ${state.party.seed || '(none)'}`);
  console.log(`Deck: ${state.party.config?.deck || '(unset)'}`);
  console.log(`Stake: ${state.party.config?.stake || '(unset)'}`);
  console.log(`Boss Ante: ${state.party.config?.bossAnte || '(unknown)'}`);
  if (state.party.countdownStartedAt) {
    console.log(`Countdown Starts At: ${new Date(state.party.countdownStartedAt).toISOString()}`);
  }
  if (state.party.winnerPlayerId) {
    console.log(`Winner: ${state.party.winnerPlayerId}`);
    console.log(`Result Reason: ${state.party.resultReason}`);
  }

  console.log('Players:');
  for (const player of state.party.players || []) {
    const tags = [];
    if (player.playerId === state.playerId) tags.push('YOU');
    if (player.isHost) tags.push('HOST');
    if (player.connected) tags.push('CONNECTED');
    if (player.ready) tags.push('READY');
    if (player.reachedBoss) tags.push('AT_BOSS');
    if (player.bossReady) tags.push('BOSS_READY');
    if (player.finishedBoss) tags.push('FINISHED');
    if (player.eliminated) tags.push('ELIMINATED');

    console.log(`- ${player.name} (${player.playerId}) [${tags.join(', ') || 'NONE'}]`);
    console.log(
      `  Runtime: ante=${player.runtime?.ante ?? 0}, score=${player.runtime?.score ?? 0}, handsUsed=${player.runtime?.handsUsed ?? 0}, handsRemaining=${player.runtime?.handsRemaining ?? 'null'}, money=${player.runtime?.money ?? 0}`
    );
  }
  printDivider();
}

function printEvents(events) {
  if (!events || !events.length) return;
  console.log('New events:');
  for (const event of events) {
    console.log(`- #${event.eventId} ${event.type} @ ${new Date(event.at).toISOString()}`);
    if (event.data && Object.keys(event.data).length) {
      console.log(`  ${JSON.stringify(event.data)}`);
    }
  }
  printDivider();
}

async function refreshParty() {
  if (!hasSession()) {
    console.log('No party/session yet.');
    return;
  }

  const query = `?playerId=${encodeURIComponent(state.playerId)}&playerToken=${encodeURIComponent(state.playerToken)}`;
  const data = await get(`/party/${encodeURIComponent(state.partyCode)}${query}`);
  updatePartyFromResponse(data);
  printPartySummary();
}

async function pollEvents() {
  if (!hasSession()) {
    console.log('No party/session yet.');
    return;
  }

  const query = `?playerId=${encodeURIComponent(state.playerId)}&playerToken=${encodeURIComponent(state.playerToken)}&since=${encodeURIComponent(state.lastEventId)}`;
  const data = await get(`/party/${encodeURIComponent(state.partyCode)}/events${query}`);
  updatePartyFromResponse(data);

  if (Array.isArray(data.events) && data.events.length) {
    for (const event of data.events) {
      if (typeof event.eventId === 'number') {
        state.lastEventId = Math.max(state.lastEventId, event.eventId);
      }
    }
    printEvents(data.events);
  } else {
    console.log('No new events.');
    printDivider();
  }

  printPartySummary();
}

function getAvailableCommands() {
  if (!hasSession() || !state.party) {
    return [
      { cmd: 'create [name]', desc: 'Create a new party as host' },
      { cmd: 'join <partyCode> [name]', desc: 'Join an existing party' },
      { cmd: 'health', desc: 'Check server health' },
      { cmd: 'help', desc: 'Show commands' },
      { cmd: 'exit', desc: 'Quit test client' },
    ];
  }

  const commands = [
    { cmd: 'status', desc: 'Show current party snapshot' },
    { cmd: 'poll', desc: 'Poll event endpoint and print updates' },
    { cmd: 'health', desc: 'Check server health' },
    { cmd: 'help', desc: 'Show commands' },
    { cmd: 'exit', desc: 'Quit test client' },
  ];

  const partyState = state.party.state;

  if (partyState === MATCH_STATES.LOBBY) {
    commands.push({ cmd: 'ready <true|false>', desc: 'Set ready state' });
    commands.push({ cmd: 'leave', desc: 'Leave the party while in lobby' });

    if (isHost()) {
      commands.push({ cmd: 'select <deck> <stake>', desc: 'Set deck and stake as host' });
      commands.push({ cmd: 'start', desc: 'Start the match as host' });
    }
  }

  if (partyState === MATCH_STATES.RUNNING_TO_BOSS) {
    commands.push({ cmd: 'reached_boss [ante]', desc: 'Mark yourself as having reached the boss' });
  }

  if (partyState === MATCH_STATES.WAITING_AT_BOSS) {
    commands.push({ cmd: 'boss_ready', desc: 'Mark yourself ready for the boss countdown' });
    commands.push({ cmd: 'reached_boss [ante]', desc: 'Re-send reached boss signal if needed' });
  }

  if (partyState === MATCH_STATES.BOSS_COUNTDOWN) {
    commands.push({ cmd: 'poll', desc: 'Poll until boss becomes active' });
  }

  if (partyState === MATCH_STATES.BOSS_ACTIVE || partyState === MATCH_STATES.BOSS_RESOLVED) {
    commands.push({
      cmd: 'report <score> <handsUsed> <handsRemaining|null> <money> <finished:true|false> <eliminated:true|false> [ante]',
      desc: 'Submit boss score state',
    });
  }

  return commands;
}

function printCommands() {
  printDivider();
  console.log('Commands available right now:');
  for (const item of getAvailableCommands()) {
    console.log(`- ${item.cmd}`);
    console.log(`  ${item.desc}`);
  }
  printDivider();
}

function parseBool(value) {
  if (typeof value === 'boolean') return value;
  if (value === 'true' || value === '1' || value === 'yes') return true;
  if (value === 'false' || value === '0' || value === 'no') return false;
  throw new Error(`Invalid boolean: ${value}`);
}

function parseNullableNumber(value) {
  if (value === undefined || value === null || value === 'null') return null;
  const n = Number(value);
  if (Number.isNaN(n)) throw new Error(`Invalid number: ${value}`);
  return n;
}

async function handleCommand(input) {
  const trimmed = String(input || '').trim();
  if (!trimmed) return;

  const parts = trimmed.split(/\s+/);
  const command = parts[0].toLowerCase();
  const args = parts.slice(1);

  if (command === 'help') {
    printCommands();
    return;
  }

  if (command === 'exit' || command === 'quit') {
    state.running = false;
    return;
  }

  if (command === 'health') {
    const data = await get('/health');
    console.log(JSON.stringify(data, null, 2));
    printDivider();
    return;
  }

  if (command === 'create') {
    if (hasSession()) throw new Error('Already in a party/session. Restart or leave first.');
    const name = args.join(' ') || PLAYER_NAME;
    const data = await post('/party/create', { name });
    state.playerId = data.playerId;
    state.playerToken = data.playerToken;
    state.partyCode = data.partyCode;
    updatePartyFromResponse(data);
    console.log(`Created party ${state.partyCode} as player ${state.playerId}`);
    printPartySummary();
    return;
  }

  if (command === 'join') {
    if (hasSession()) throw new Error('Already in a party/session. Restart or leave first.');
    if (!args[0]) throw new Error('Usage: join <partyCode> [name]');
    const partyCode = args[0].toUpperCase();
    const name = args.slice(1).join(' ') || PLAYER_NAME;
    const data = await post('/party/join', { partyCode, name });
    state.playerId = data.playerId;
    state.playerToken = data.playerToken;
    state.partyCode = data.partyCode;
    updatePartyFromResponse(data);
    console.log(`Joined party ${state.partyCode} as player ${state.playerId}`);
    printPartySummary();
    return;
  }

  if (!hasSession() || !state.party) {
    throw new Error('No active session. Use create or join first.');
  }

  if (command === 'status') {
    await refreshParty();
    return;
  }

  if (command === 'poll') {
    await pollEvents();
    return;
  }

  if (command === 'leave') {
    if (state.party.state !== MATCH_STATES.LOBBY) {
      throw new Error('leave is only valid in LOBBY');
    }

    await post('/party/leave', authBody());
    console.log('Left party.');
    state.playerId = null;
    state.playerToken = null;
    state.partyCode = null;
    state.party = null;
    state.lastEventId = 0;
    printDivider();
    return;
  }

  if (command === 'ready') {
    if (state.party.state !== MATCH_STATES.LOBBY) {
      throw new Error('ready is only valid in LOBBY');
    }
    if (!args[0]) throw new Error('Usage: ready <true|false>');

    const ready = parseBool(args[0]);
    const data = await post('/party/ready', authBody({ ready }));
    updatePartyFromResponse(data);
    printPartySummary();
    return;
  }

  if (command === 'select') {
    if (state.party.state !== MATCH_STATES.LOBBY) {
      throw new Error('select is only valid in LOBBY');
    }
    if (!isHost()) {
      throw new Error('Only the host can use select');
    }
    if (args.length < 2) throw new Error('Usage: select <deck> <stake>');

    const deck = args[0];
    const stake = args[1];
    const data = await post('/party/select', authBody({ deck, stake }));
    updatePartyFromResponse(data);
    printPartySummary();
    return;
  }

  if (command === 'start') {
    if (state.party.state !== MATCH_STATES.LOBBY) {
      throw new Error('start is only valid in LOBBY');
    }
    if (!isHost()) {
      throw new Error('Only the host can start');
    }

    const data = await post('/party/start', authBody());
    updatePartyFromResponse(data);
    printPartySummary();
    return;
  }

  if (command === 'reached_boss') {
    if (![MATCH_STATES.RUNNING_TO_BOSS, MATCH_STATES.WAITING_AT_BOSS].includes(state.party.state)) {
      throw new Error('reached_boss is only valid in RUNNING_TO_BOSS or WAITING_AT_BOSS');
    }

    const ante = args[0] ? Number(args[0]) : undefined;
    const data = await post('/match/reached_boss', authBody({ ante }));
    updatePartyFromResponse(data);
    printPartySummary();
    return;
  }

  if (command === 'boss_ready') {
    if (![MATCH_STATES.WAITING_AT_BOSS, MATCH_STATES.BOSS_COUNTDOWN].includes(state.party.state)) {
      throw new Error('boss_ready is only valid in WAITING_AT_BOSS or BOSS_COUNTDOWN');
    }

    const data = await post('/match/boss_ready', authBody());
    updatePartyFromResponse(data);
    printPartySummary();
    return;
  }

  if (command === 'report') {
    if (![MATCH_STATES.BOSS_ACTIVE, MATCH_STATES.BOSS_RESOLVED].includes(state.party.state)) {
      throw new Error('report is only valid in BOSS_ACTIVE or BOSS_RESOLVED');
    }
    if (args.length < 6) {
      throw new Error('Usage: report <score> <handsUsed> <handsRemaining|null> <money> <finished:true|false> <eliminated:true|false> [ante]');
    }

    const score = Number(args[0]);
    const handsUsed = Number(args[1]);
    const handsRemaining = parseNullableNumber(args[2]);
    const money = Number(args[3]);
    const finished = parseBool(args[4]);
    const eliminated = parseBool(args[5]);
    const ante = args[6] ? Number(args[6]) : undefined;

    if ([score, handsUsed, money].some(Number.isNaN)) {
      throw new Error('score, handsUsed, and money must be valid numbers');
    }
    if (ante !== undefined && Number.isNaN(ante)) {
      throw new Error('ante must be a valid number when provided');
    }

    const data = await post('/match/report_state', authBody({
      score,
      handsUsed,
      handsRemaining,
      money,
      finished,
      eliminated,
      ante,
    }));

    updatePartyFromResponse(data);
    printPartySummary();
    return;
  }

  throw new Error(`Unknown or unavailable command in current state: ${command}`);
}

async function main() {
  console.log('Balatro PvP Polling Test Client');
  console.log(`Server: ${BASE_URL}`);
  printCommands();

    let lastPollTime = 0;
    const POLL_INTERVAL_MS = 2000;

    while (state.running) {
    try {
        const now = Date.now();

        // 🔁 Auto poll every 5 seconds
        if (hasSession() && now - lastPollTime >= POLL_INTERVAL_MS) {
        try {
            await pollEvents();
        } catch (e) {
            printError(e);
        }
        lastPollTime = now;
        }

        const prompt = state.party ? `[${state.party.state}]> ` : '> ';
        
        const input = readlineSync.question(prompt);
        await handleCommand(input);

    } catch (error) {
        printError(error);
        printDivider();
    }
    }
  console.log('Goodbye.');
}

main().catch((error) => {
  printError(error);
  process.exit(1);
});
