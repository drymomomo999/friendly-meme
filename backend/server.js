import express from "express";
import cors from "cors";

import { getStore, saveStore, nextId, nowDate, addXpForTask, recomputeLevel } from "./db.js";

getStore();

const app = express();
app.use(cors());
app.use(express.json({ limit: "1mb" }));

const PORT = process.env.PORT ? Number(process.env.PORT) : 3001;
const USER_ID = 1;

function styleHeader(style, lang) {
  const isEn = lang === "en";
  if (style === "strict") return isEn ? "Minimal next action. Do it now." : "只给你最小可执行动作，直接做。";
  if (style === "mentor")
    return isEn ? "I’ll explain the why and the done criteria." : "我会解释理由与验证标准，帮你稳步推进。";
  return isEn ? "We’ll make it easy to start together." : "我们一起把它变得更容易开始。";
}

function heuristicPlan({ title, deadline, weeklyHours, lang }) {
  const wh = Math.max(1, Number(weeklyHours || 5));
  const dl = deadline || null;
  const isEn = lang === "en";

  if (isEn) {
    return [
      {
        title: "Clarify success criteria",
        due_date: dl,
        tasks: [
          { title: `Write what “done” means for: ${title}`, estimated_minutes: 25, difficulty: 1 },
          { title: "List resources & constraints (time/tools/environment)", estimated_minutes: 25, difficulty: 1 }
        ]
      },
      {
        title: "Break into milestones & weekly rhythm",
        due_date: dl,
        tasks: [
          { title: `Estimate a pace with ${wh} hours/week`, estimated_minutes: 25, difficulty: 2 },
          { title: "Draft 3–5 milestones", estimated_minutes: 50, difficulty: 2 }
        ]
      },
      {
        title: "Execution & review loop",
        due_date: dl,
        tasks: [
          { title: "Define your daily MIT rule", estimated_minutes: 25, difficulty: 1 },
          { title: "Do one 30-second daily review", estimated_minutes: 10, difficulty: 1 }
        ]
      }
    ];
  }

  return [
    {
      title: "澄清目标与完成标准",
      due_date: dl,
      tasks: [
        { title: `写下“完成 ${title}”的标准`, estimated_minutes: 25, difficulty: 1 },
        { title: "列出资源与约束（时间/工具/环境）", estimated_minutes: 25, difficulty: 1 }
      ]
    },
    {
      title: "拆解里程碑与周节奏",
      due_date: dl,
      tasks: [
        { title: `按每周 ${wh} 小时估算节奏`, estimated_minutes: 25, difficulty: 2 },
        { title: "把目标拆成 3-5 个里程碑", estimated_minutes: 50, difficulty: 2 }
      ]
    },
    {
      title: "执行与复盘循环",
      due_date: dl,
      tasks: [
        { title: "设定每日最小任务（MIT）规则", estimated_minutes: 25, difficulty: 1 },
        { title: "完成一次 30 秒日复盘", estimated_minutes: 10, difficulty: 1 }
      ]
    }
  ];
}

function getGoalOrThrow(s, goalId) {
  const goal = s.goals.find((g) => g.id === goalId && g.user_id === USER_ID);
  if (!goal) throw new Error("Goal not found");
  return goal;
}

function getMilestonesByGoal(s, goalId) {
  return s.milestones
    .filter((m) => m.goal_id === goalId)
    .sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0) || a.id - b.id);
}

function getTasksByGoal(s, goalId) {
  const msIds = new Set(getMilestonesByGoal(s, goalId).map((m) => m.id));
  return s.tasks
    .filter((t) => msIds.has(t.milestone_id))
    .sort((a, b) => {
      const aSch = a.scheduled_date || "9999-12-31";
      const bSch = b.scheduled_date || "9999-12-31";
      if (a.status !== b.status) return String(a.status).localeCompare(String(b.status));
      if (aSch !== bSch) return aSch.localeCompare(bSch);
      return a.id - b.id;
    });
}

app.get("/api/health", (req, res) => {
  res.json({ ok: true });
});

app.get("/api/goals", (req, res) => {
  const s = getStore();
  const goals = s.goals.filter((g) => g.user_id === USER_ID).sort((a, b) => b.id - a.id);
  res.json({ goals });
});

app.post("/api/goals", (req, res) => {
  const s = getStore();
  const { title, deadline, weeklyHours } = req.body || {};
  if (!title || typeof title !== "string") return res.status(400).json({ error: "title required" });

  const id = nextId("goal");
  const goal = {
    id,
    user_id: USER_ID,
    title: title.trim(),
    deadline: deadline || null,
    weekly_hours: Math.max(1, Number(weeklyHours || 5)),
    status: "active",
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  };
  s.goals.push(goal);
  saveStore();
  res.json({ goal });
});

app.get("/api/goals/:id/plan", (req, res) => {
  const s = getStore();
  const goalId = Number(req.params.id);
  const goal = getGoalOrThrow(s, goalId);

  const milestones = getMilestonesByGoal(s, goalId);
  const msIds = new Set(milestones.map((m) => m.id));
  const tasks = s.tasks
    .filter((t) => msIds.has(t.milestone_id))
    .sort((a, b) => (a.status || "").localeCompare(b.status || "") || a.id - b.id);

  res.json({ goal, milestones, tasks });
});

app.post("/api/goals/:id/generate-plan", (req, res) => {
  const s = getStore();
  const goalId = Number(req.params.id);
  const goal = getGoalOrThrow(s, goalId);

  const { style, lang } = req.body || {};
  const plan = heuristicPlan({
    title: goal.title,
    deadline: goal.deadline,
    weeklyHours: goal.weekly_hours,
    lang: lang || "zh"
  });

  const oldMs = s.milestones.filter((m) => m.goal_id === goalId).map((m) => m.id);
  const oldMsSet = new Set(oldMs);
  s.tasks = s.tasks.filter((t) => !oldMsSet.has(t.milestone_id));
  s.milestones = s.milestones.filter((m) => m.goal_id !== goalId);

  let order = 0;
  for (const ms of plan) {
    const milestoneId = nextId("milestone");
    s.milestones.push({
      id: milestoneId,
      goal_id: goalId,
      title: ms.title,
      start_date: null,
      due_date: ms.due_date || null,
      sort_order: order++,
      status: "active",
      created_at: new Date().toISOString()
    });

    for (const t of ms.tasks || []) {
      s.tasks.push({
        id: nextId("task"),
        milestone_id: milestoneId,
        title: t.title,
        description: t.description || null,
        estimated_minutes: Math.max(5, Number(t.estimated_minutes || 25)),
        difficulty: Math.min(3, Math.max(1, Number(t.difficulty || 2))),
        weight: Number(t.weight || 1.0),
        scheduled_date: t.scheduled_date || null,
        status: "todo",
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      });
    }
  }

  saveStore();
  const isEn = lang === "en";
  res.json({
    ok: true,
    coach: {
      style: style || "gentle",
      message: isEn
        ? `${styleHeader(style || "gentle", "en")} I generated an initial plan for “${goal.title}”.`
        : `${styleHeader(style || "gentle", "zh")} 我已经为“${goal.title}”生成了一个可执行的初版计划。`
    }
  });
});

app.get("/api/today", (req, res) => {
  const s = getStore();
  const goalId = Number(req.query.goalId);
  const date = (req.query.date && String(req.query.date)) || nowDate();
  const goal = getGoalOrThrow(s, goalId);

  const tasks = getTasksByGoal(s, goalId);
  const scheduled = tasks.filter((t) => t.status !== "done" && t.scheduled_date === date);
  const pick = (scheduled.length ? scheduled : tasks.filter((t) => t.status !== "done")).slice(0, 3);

  res.json({ goal, date, tasks: pick });
});

app.patch("/api/tasks/:id", (req, res) => {
  const s = getStore();
  const taskId = Number(req.params.id);
  const patch = req.body || {};

  const task = s.tasks.find((t) => t.id === taskId);
  if (!task) return res.status(404).json({ error: "task not found" });

  const allowed = ["title", "description", "estimated_minutes", "difficulty", "scheduled_date", "status"];
  for (const k of allowed) {
    if (patch[k] === undefined) continue;
    task[k] = patch[k] === "" ? null : patch[k];
  }
  task.updated_at = new Date().toISOString();
  saveStore();
  res.json({ ok: true, task });
});

app.post("/api/tasks/:id/complete", (req, res) => {
  const s = getStore();
  const taskId = Number(req.params.id);
  const { spentMinutes, note, date } = req.body || {};
  const completedDate = (date && String(date)) || nowDate();

  const task = s.tasks.find((t) => t.id === taskId);
  if (!task) return res.status(404).json({ error: "task not found" });

  const milestone = s.milestones.find((m) => m.id === task.milestone_id);
  if (!milestone) return res.status(400).json({ error: "milestone not found" });
  const goalId = milestone.goal_id;

  task.status = "done";
  task.updated_at = new Date().toISOString();

  s.checkins.push({
    id: nextId("checkin"),
    task_id: taskId,
    goal_id: goalId,
    spent_minutes: Math.max(0, Number(spentMinutes || 0)),
    note: note || null,
    completed_at: new Date().toISOString(),
    completed_date: completedDate
  });

  const rs = s.reward_state[USER_ID] || {
    user_id: USER_ID,
    xp: 0,
    level: 1,
    streak: 0,
    shields: 0,
    last_active_date: null
  };

  const xpAdd = addXpForTask({
    estimatedMinutes: task.estimated_minutes,
    difficulty: task.difficulty,
    spentMinutes
  });

  const todayCount = s.checkins.filter((c) => c.goal_id === goalId && c.completed_date === completedDate).length;
  let newStreak = rs.streak || 0;
  if (todayCount === 1) {
    const last = rs.last_active_date;
    const d = new Date(completedDate + "T00:00:00.000Z");
    const y = new Date(d);
    y.setUTCDate(y.getUTCDate() - 1);
    const yesterday = y.toISOString().slice(0, 10);

    if (!last) newStreak = 1;
    else if (last === completedDate) newStreak = rs.streak || 0;
    else if (last === yesterday) newStreak = (rs.streak || 0) + 1;
    else newStreak = 1;
  }

  const newXp = (rs.xp || 0) + xpAdd;
  const newLevel = recomputeLevel(newXp);

  s.reward_state[USER_ID] = {
    ...rs,
    xp: newXp,
    level: newLevel,
    streak: newStreak,
    last_active_date: completedDate
  };

  saveStore();

  res.json({
    ok: true,
    reward: { xp: newXp, level: newLevel, streak: newStreak, xpAdd }
  });
});

app.post("/api/reviews", (req, res) => {
  const s = getStore();
  const { goalId, reviewDate, doneSummary, blockers, mood, nextAction } = req.body || {};
  const gid = Number(goalId);
  getGoalOrThrow(s, gid);

  const d = reviewDate || nowDate();
  const existing = s.daily_reviews.find((r) => r.goal_id === gid && r.review_date === d);

  if (existing) {
    existing.done_summary = doneSummary || null;
    existing.blockers = blockers || null;
    existing.mood = mood ?? null;
    existing.next_action = nextAction || null;
  } else {
    s.daily_reviews.push({
      id: nextId("review"),
      goal_id: gid,
      review_date: d,
      done_summary: doneSummary || null,
      blockers: blockers || null,
      mood: mood ?? null,
      next_action: nextAction || null,
      created_at: new Date().toISOString()
    });
  }

  saveStore();
  res.json({ ok: true });
});

app.post("/api/coach/stuck", (req, res) => {
  const s = getStore();
  const { goalId, taskId, message, style, lang } = req.body || {};
  const gid = Number(goalId);
  const goal = getGoalOrThrow(s, gid);

  const focusTask = taskId ? s.tasks.find((t) => t.id === Number(taskId)) : null;
  const focus = focusTask ? focusTask.title : goal.title;
  const isEn = lang === "en";
  const base = styleHeader(style || "gentle", isEn ? "en" : "zh");

  const steps = isEn
    ? [
        `Shrink “${focus}” into a 10-minute step: write 3 bullets / list 3 substeps / open a file and write a title.`,
        "If unclear: write one sentence of “done criteria”, then find the shortest working example.",
        "If fear/avoidance: only do the start action for 10 minutes, then you’re allowed to stop."
      ]
    : [
        `把“${focus}”缩小成 10 分钟内能完成的一步：写 3 行要点/列 3 个子步骤/开一个文件并写标题。`,
        "如果是不清楚：先写“完成标准”一句话，再找一个最短示例参考。",
        "如果是畏难：只做开始动作（打开工具/创建文件/写第一句），计时 10 分钟后允许停。"
      ];

  const tone = isEn
    ? style === "strict"
      ? "Start now: do only the first step for 10 minutes. Then report: done / not done + reason."
      : style === "mentor"
        ? "Stuck usually means the scope is too big or the definition is unclear. Run a tiny experiment for feedback."
        : "It’s okay. Let’s shrink it until it’s easy to start."
    : style === "strict"
      ? "现在开始：只做第一步，10 分钟。结束后告诉我“完成/未完成 + 原因”。"
      : style === "mentor"
        ? "卡住通常是范围过大或标准不清。先用最小实验跑出反馈。"
        : "没关系，我们把它拆小到“马上能开始”的程度。";

  res.json({
    ok: true,
    coach: {
      style: style || "gentle",
      header: base,
      note: tone,
      context: { goal: goal.title, task: focusTask ? focusTask.title : null, message: message || "" },
      nextSteps: steps
    }
  });
});

app.get("/api/progress", (req, res) => {
  const s = getStore();
  const goalId = Number(req.query.goalId);
  const from = (req.query.from && String(req.query.from)) || null;
  const to = (req.query.to && String(req.query.to)) || null;

  const goal = getGoalOrThrow(s, goalId);

  const checkins = s.checkins.filter((c) => {
    if (c.goal_id !== goalId) return false;
    if (from && c.completed_date < from) return false;
    if (to && c.completed_date > to) return false;
    return true;
  });

  const dailyMap = new Map();
  for (const c of checkins) {
    const key = c.completed_date;
    const cur = dailyMap.get(key) || { date: key, done_count: 0, spent_minutes: 0 };
    cur.done_count += 1;
    cur.spent_minutes += Number(c.spent_minutes || 0);
    dailyMap.set(key, cur);
  }

  const daily = Array.from(dailyMap.values()).sort((a, b) => a.date.localeCompare(b.date));

  const tasks = getTasksByGoal(s, goalId);
  const totalTasks = tasks.length;
  const doneTasks = tasks.filter((t) => t.status === "done").length;

  res.json({
    goal,
    daily,
    summary: {
      totalTasks,
      doneTasks,
      completionRate: totalTasks ? doneTasks / totalTasks : 0
    },
    reward: s.reward_state[USER_ID]
  });
});

app.listen(PORT, () => {
  console.log(`Backend listening on http://localhost:${PORT}`);
});
