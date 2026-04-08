import fs from "fs";
import path from "path";

const storePath = path.join(process.cwd(), "data.json");
let store = null;

function defaultStore() {
  return {
    nextIds: { goal: 1, milestone: 1, task: 1, checkin: 1, review: 1 },
    users: [{ id: 1, created_at: new Date().toISOString() }],
    goals: [],
    milestones: [],
    tasks: [],
    checkins: [],
    daily_reviews: [],
    reward_state: {
      1: { user_id: 1, xp: 0, level: 1, streak: 0, shields: 0, last_active_date: null }
    }
  };
}

export function initStore() {
  if (store) return store;
  if (!fs.existsSync(storePath)) {
    store = defaultStore();
    saveStore();
    return store;
  }

  try {
    const raw = fs.readFileSync(storePath, "utf-8");
    const parsed = JSON.parse(raw);
    store = parsed && typeof parsed === "object" ? parsed : defaultStore();
  } catch {
    store = defaultStore();
  }

  if (!store.reward_state) store.reward_state = {};
  if (!store.reward_state[1]) {
    store.reward_state[1] = { user_id: 1, xp: 0, level: 1, streak: 0, shields: 0, last_active_date: null };
  }

  if (!store.nextIds) store.nextIds = { goal: 1, milestone: 1, task: 1, checkin: 1, review: 1 };

  saveStore();
  return store;
}

export function getStore() {
  return initStore();
}

export function saveStore() {
  if (!store) return;
  const tmp = storePath + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(store, null, 2), "utf-8");
  fs.renameSync(tmp, storePath);
}

export function nextId(kind) {
  const s = getStore();
  const n = Number(s.nextIds?.[kind] || 1);
  s.nextIds[kind] = n + 1;
  return n;
}

export function nowDate() {
  return new Date().toISOString().slice(0, 10);
}

export function addXpForTask({ estimatedMinutes, difficulty, spentMinutes }) {
  const blocks = Math.max(1, Math.ceil((estimatedMinutes || spentMinutes || 25) / 25));
  const base = 10 * blocks * Math.min(3, Math.max(1, difficulty || 2));
  return Math.min(300, base);
}

export function recomputeLevel(xp) {
  return Math.max(1, Math.floor((xp || 0) / 500) + 1);
}
