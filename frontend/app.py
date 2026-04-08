import os
import datetime as dt

import pandas as pd
import requests
import streamlit as st

BACKEND_URL = os.getenv("BACKEND_URL", "http://localhost:3001")

st.set_page_config(page_title="Hertell", layout="wide")
st.set_option("browser.gatherUsageStats", False)

TRANSLATIONS = {
    "zh": {
        "sidebar.title": "Hertell",
        "sidebar.language": "语言",
        "sidebar.goal": "当前目标",
        "page.start": "开始",
        "page.today": "今日",
        "page.plan": "计划",
        "page.review": "复盘",
        "page.progress": "进度",
        "page.settings": "设置",
        "start.header": "创建目标",
        "start.title": "一句话目标",
        "start.title.placeholder": "例如：30 天搭建一个能持续使用的学习平台",
        "start.deadline": "期限（可选）",
        "start.weekly_hours": "每周可投入小时",
        "start.style": "AI 风格",
        "start.submit": "创建并生成计划",
        "start.created": "已创建目标并生成计划",
        "start.existing": "已有目标",
        "today.need_goal": "先在「开始」创建一个目标",
        "today.header": "今天只做最关键的 1–3 件事",
        "today.none": "今天没有待办任务了",
        "today.caption.zh": "预计 {minutes} 分钟｜难度 {difficulty}/3｜状态 {status}",
        "today.spent": "实际用时（分钟）",
        "today.note": "备注",
        "today.note.placeholder": "可选",
        "today.done": "完成",
        "today.reward": "获得 XP +{xp_add}｜等级 {level}｜连击 {streak} 天",
        "today.stuck": "我卡住了",
        "today.stuck.desc": "描述你卡住的点（选填）",
        "today.stuck.placeholder": "例如：不知道从哪开始/觉得任务太大/没有资料",
        "today.stuck.button": "给我下一步动作",
        "plan.header": "计划与任务",
        "plan.caption.zh": "期限：{deadline}｜每周：{weekly_hours} 小时",
        "plan.caption.en": "Deadline: {deadline} | Weekly: {weekly_hours}h",
        "plan.not_set.zh": "未设置",
        "plan.not_set.en": "Not set",
        "plan.regenerate": "重新生成计划（会覆盖当前任务）",
        "plan.regenerate.done": "已重新生成",
        "plan.task.title": "任务 #{task_id} 标题",
        "plan.task.date": "任务 #{task_id} 日期",
        "plan.task.minutes": "任务 #{task_id} 分钟",
        "plan.task.difficulty": "任务 #{task_id} 难度",
        "plan.save": "保存",
        "review.header": "30 秒日复盘",
        "review.date": "日期",
        "review.done": "今天完成了什么？（一句话）",
        "review.done.placeholder": "例如：完成了 2 个 MIT，并把计划拆小了",
        "review.blockers": "阻碍是什么？",
        "review.blockers.placeholder": "例如：任务太大/标准不清/时间碎片化",
        "review.mood": "心情/动力（可选）",
        "review.next": "明天最小动作是什么？",
        "review.next.placeholder": "例如：只做 10 分钟开始动作，写 3 行提纲",
        "review.submit": "保存复盘",
        "review.saved": "已保存",
        "progress.header": "进度与奖励",
        "progress.completion": "完成率",
        "progress.xp": "XP",
        "progress.level": "等级",
        "progress.streak": "连击天数",
        "progress.trend": "近 30 天完成趋势",
        "progress.time": "用时（分钟）",
        "progress.empty": "还没有完成记录。去「今日」做一个最小任务开始。",
        "settings.header": "设置",
        "settings.style": "AI 风格",
        "settings.saved": "已保存到本次会话。",
        "settings.backend": "后端地址：{backend_url}",
        "style.gentle": "温和陪伴",
        "style.strict": "严格监督",
        "style.mentor": "专业导师",
        "status.todo": "待做",
        "status.done": "已完成",
    },
    "en": {
        "sidebar.title": "Hertell",
        "sidebar.language": "Language",
        "sidebar.goal": "Active goal",
        "page.start": "Start",
        "page.today": "Today",
        "page.plan": "Plan",
        "page.review": "Review",
        "page.progress": "Progress",
        "page.settings": "Settings",
        "start.header": "Create a Goal",
        "start.title": "One-line goal",
        "start.title.placeholder": "e.g. Build a motivating learning platform in 30 days",
        "start.deadline": "Deadline (optional)",
        "start.weekly_hours": "Hours per week",
        "start.style": "AI Style",
        "start.submit": "Create & Generate Plan",
        "start.created": "Goal created and plan generated",
        "start.existing": "Existing goals",
        "today.need_goal": "Create a goal in “Start” first",
        "today.header": "Focus on 1–3 most important tasks today",
        "today.none": "No pending tasks for today",
        "today.caption.en": "{minutes} min | diff {difficulty}/3 | {status}",
        "today.spent": "Time spent (min)",
        "today.note": "Note",
        "today.note.placeholder": "Optional",
        "today.done": "Done",
        "today.reward": "XP +{xp_add} | Level {level} | Streak {streak} days",
        "today.stuck": "I'm stuck",
        "today.stuck.desc": "Describe what you're stuck on (optional)",
        "today.stuck.placeholder": "e.g. don't know where to start / too big / missing resources",
        "today.stuck.button": "Give me the next step",
        "plan.header": "Plan & Tasks",
        "plan.regenerate": "Regenerate plan (overwrites current tasks)",
        "plan.regenerate.done": "Regenerated",
        "plan.task.title": "Task #{task_id} title",
        "plan.task.date": "Task #{task_id} date",
        "plan.task.minutes": "Task #{task_id} minutes",
        "plan.task.difficulty": "Task #{task_id} difficulty",
        "plan.save": "Save",
        "review.header": "30-second Daily Review",
        "review.date": "Date",
        "review.done": "What did you finish today? (one sentence)",
        "review.done.placeholder": "e.g. finished 2 MITs and made the plan smaller",
        "review.blockers": "What blocked you?",
        "review.blockers.placeholder": "e.g. task too big / unclear definition / fragmented time",
        "review.mood": "Mood / motivation (optional)",
        "review.next": "What's your smallest next action for tomorrow?",
        "review.next.placeholder": "e.g. start for 10 minutes and write 3 bullet points",
        "review.submit": "Save review",
        "review.saved": "Saved",
        "progress.header": "Progress & Rewards",
        "progress.completion": "Completion",
        "progress.xp": "XP",
        "progress.level": "Level",
        "progress.streak": "Streak",
        "progress.trend": "Last 30 days completion",
        "progress.time": "Time spent (min)",
        "progress.empty": "No completion yet. Go to “Today” and finish a tiny task to start.",
        "settings.header": "Settings",
        "settings.style": "AI Style",
        "settings.saved": "Saved in this session.",
        "settings.backend": "Backend URL: {backend_url}",
        "style.gentle": "Gentle",
        "style.strict": "Strict",
        "style.mentor": "Mentor",
        "status.todo": "To do",
        "status.done": "Done",
    },
}


def get_lang():
    if "lang" not in st.session_state:
        st.session_state.lang = "zh"
    return st.session_state.lang


def t(key):
    return TRANSLATIONS.get(get_lang(), TRANSLATIONS["zh"]).get(key, key)


def fmt(key, **kwargs):
    return t(key).format(**kwargs)


def api_get(path, params=None):
    r = requests.get(f"{BACKEND_URL}{path}", params=params, timeout=30)
    r.raise_for_status()
    return r.json()


def api_post(path, payload=None):
    r = requests.post(f"{BACKEND_URL}{path}", json=payload or {}, timeout=30)
    r.raise_for_status()
    return r.json()


def api_patch(path, payload=None):
    r = requests.patch(f"{BACKEND_URL}{path}", json=payload or {}, timeout=30)
    r.raise_for_status()
    return r.json()


if "style" not in st.session_state:
    st.session_state.style = "gentle"
if "active_goal_id" not in st.session_state:
    st.session_state.active_goal_id = None

st.sidebar.title(t("sidebar.title"))
lang = st.sidebar.selectbox(
    t("sidebar.language"),
    ["zh", "en"],
    index=["zh", "en"].index(get_lang()),
    format_func=lambda x: "中文" if x == "zh" else "English",
)
st.session_state.lang = lang

page_ids = ["start", "today", "plan", "review", "progress", "settings"]
page = st.sidebar.radio(
    "page",
    page_ids,
    index=0,
    format_func=lambda x: t(f"page.{x}"),
    label_visibility="collapsed",
)


def goal_picker():
    data = api_get("/api/goals")
    goals = data.get("goals", [])
    if not goals:
        st.session_state.active_goal_id = None
        return None

    options = {f"#{g['id']} {g['title']}": g["id"] for g in goals}
    labels = list(options.keys())
    default_label = labels[0]
    if st.session_state.active_goal_id:
        for lbl, gid in options.items():
            if gid == st.session_state.active_goal_id:
                default_label = lbl
                break
    selected = st.sidebar.selectbox(t("sidebar.goal"), labels, index=labels.index(default_label))
    st.session_state.active_goal_id = options[selected]
    return st.session_state.active_goal_id


active_goal_id = goal_picker()

if page == "start":
    st.header(t("start.header"))
    with st.form("create_goal"):
        title = st.text_input(t("start.title"), placeholder=t("start.title.placeholder"))
        col1, col2, col3 = st.columns(3)
        with col1:
            deadline = st.date_input(t("start.deadline"), value=None)
        with col2:
            weekly_hours = st.number_input(t("start.weekly_hours"), min_value=1, max_value=80, value=5, step=1)
        with col3:
            style = st.selectbox(
                t("start.style"),
                ["gentle", "strict", "mentor"],
                index=["gentle", "strict", "mentor"].index(st.session_state.style),
                format_func=lambda x: t(f"style.{x}"),
            )
        submit = st.form_submit_button(t("start.submit"))

    if submit:
        d = deadline.isoformat() if deadline else None
        created = api_post("/api/goals", {"title": title, "deadline": d, "weeklyHours": int(weekly_hours)})
        goal = created["goal"]
        st.session_state.active_goal_id = goal["id"]
        st.session_state.style = style
        api_post(f"/api/goals/{goal['id']}/generate-plan", {"style": style, "lang": get_lang()})
        st.success(t("start.created"))
        st.rerun()

    st.divider()
    st.subheader(t("start.existing"))
    data = api_get("/api/goals")
    for g in data.get("goals", []):
        if get_lang() == "en":
            st.write(f"#{g['id']} {g['title']} (weekly {g['weekly_hours']}h)")
        else:
            st.write(f"#{g['id']} {g['title']}（每周 {g['weekly_hours']} 小时）")

elif page == "today":
    if not active_goal_id:
        st.info(t("today.need_goal"))
    else:
        st.header(t("today.header"))
        today = dt.date.today().isoformat()
        data = api_get("/api/today", {"goalId": active_goal_id, "date": today})
        tasks = data.get("tasks", [])

        if not tasks:
            st.success(t("today.none"))
        else:
            for task in tasks:
                with st.container(border=True):
                    c1, c2, c3 = st.columns([6, 2, 2])
                    with c1:
                        st.subheader(task["title"])
                        if task.get("description"):
                            st.write(task["description"])
                        status_label = t(f"status.{task['status']}") if task.get("status") else str(task.get("status", ""))
                        caption_key = "today.caption.en" if get_lang() == "en" else "today.caption.zh"
                        st.caption(
                            fmt(
                                caption_key,
                                minutes=task["estimated_minutes"],
                                difficulty=task["difficulty"],
                                status=status_label,
                            )
                        )
                    with c2:
                        spent = st.number_input(
                            f"{t('today.spent')} #{task['id']}",
                            min_value=0,
                            max_value=600,
                            value=int(task["estimated_minutes"]),
                            step=5,
                        )
                    with c3:
                        note = st.text_input(
                            f"{t('today.note')} #{task['id']}", placeholder=t("today.note.placeholder")
                        )
                        done = st.button(f"{t('today.done')} #{task['id']}", type="primary")
                        if done:
                            result = api_post(
                                f"/api/tasks/{task['id']}/complete",
                                {"spentMinutes": int(spent), "note": note, "date": today},
                            )
                            st.success(
                                fmt(
                                    "today.reward",
                                    xp_add=result["reward"]["xpAdd"],
                                    level=result["reward"]["level"],
                                    streak=result["reward"]["streak"],
                                )
                            )
                            st.rerun()

        st.divider()
        st.subheader(t("today.stuck"))
        msg = st.text_area(t("today.stuck.desc"), placeholder=t("today.stuck.placeholder"))
        if st.button(t("today.stuck.button"), type="secondary"):
            coach = api_post(
                "/api/coach/stuck",
                {"goalId": active_goal_id, "message": msg, "style": st.session_state.style, "lang": get_lang()},
            ).get("coach", {})
            st.write(coach.get("header", ""))
            st.write(coach.get("note", ""))
            for s in coach.get("nextSteps", []):
                st.write(f"- {s}")

elif page == "plan":
    if not active_goal_id:
        st.info(t("today.need_goal"))
    else:
        st.header(t("plan.header"))
        plan = api_get(f"/api/goals/{active_goal_id}/plan")
        goal = plan["goal"]
        st.subheader(goal["title"])
        not_set = t("plan.not_set.en") if get_lang() == "en" else t("plan.not_set.zh")
        caption_key = "plan.caption.en" if get_lang() == "en" else "plan.caption.zh"
        st.caption(fmt(caption_key, deadline=(goal["deadline"] or not_set), weekly_hours=goal["weekly_hours"]))

        if st.button(t("plan.regenerate"), type="secondary"):
            api_post(f"/api/goals/{active_goal_id}/generate-plan", {"style": st.session_state.style, "lang": get_lang()})
            st.success(t("plan.regenerate.done"))
            st.rerun()

        milestones = plan.get("milestones", [])
        tasks = plan.get("tasks", [])

        grouped = {}
        for task in tasks:
            grouped.setdefault(task["milestone_id"], []).append(task)

        for m in milestones:
            with st.expander(m["title"], expanded=True):
                for task in grouped.get(m["id"], []):
                    cols = st.columns([5, 2, 2, 2, 1])
                    with cols[0]:
                        new_title = st.text_input(
                            fmt("plan.task.title", task_id=task["id"]),
                            value=task["title"],
                            label_visibility="collapsed",
                        )
                    with cols[1]:
                        sch = st.text_input(
                            fmt("plan.task.date", task_id=task["id"]),
                            value=task["scheduled_date"] or "",
                            placeholder="YYYY-MM-DD",
                            label_visibility="collapsed",
                        )
                    with cols[2]:
                        est = st.number_input(
                            fmt("plan.task.minutes", task_id=task["id"]),
                            min_value=5,
                            max_value=600,
                            value=int(task["estimated_minutes"]),
                            step=5,
                            label_visibility="collapsed",
                        )
                    with cols[3]:
                        diff = st.number_input(
                            fmt("plan.task.difficulty", task_id=task["id"]),
                            min_value=1,
                            max_value=3,
                            value=int(task["difficulty"]),
                            step=1,
                            label_visibility="collapsed",
                        )
                    with cols[4]:
                        if st.button(t("plan.save"), key=f"save_{task['id']}"):
                            api_patch(
                                f"/api/tasks/{task['id']}",
                                {
                                    "title": new_title,
                                    "scheduled_date": sch,
                                    "estimated_minutes": int(est),
                                    "difficulty": int(diff),
                                },
                            )
                            st.rerun()

elif page == "review":
    if not active_goal_id:
        st.info(t("today.need_goal"))
    else:
        st.header(t("review.header"))
        d = st.date_input(t("review.date"), value=dt.date.today())
        with st.form("review"):
            done = st.text_area(t("review.done"), placeholder=t("review.done.placeholder"))
            blockers = st.text_area(t("review.blockers"), placeholder=t("review.blockers.placeholder"))
            mood = st.slider(t("review.mood"), min_value=1, max_value=5, value=3)
            next_action = st.text_area(t("review.next"), placeholder=t("review.next.placeholder"))
            submit = st.form_submit_button(t("review.submit"))
        if submit:
            api_post(
                "/api/reviews",
                {
                    "goalId": active_goal_id,
                    "reviewDate": d.isoformat(),
                    "doneSummary": done,
                    "blockers": blockers,
                    "mood": int(mood),
                    "nextAction": next_action,
                },
            )
            st.success(t("review.saved"))
            st.rerun()

elif page == "progress":
    if not active_goal_id:
        st.info(t("today.need_goal"))
    else:
        st.header(t("progress.header"))
        to = dt.date.today()
        frm = to - dt.timedelta(days=30)
        prog = api_get("/api/progress", {"goalId": active_goal_id, "from": frm.isoformat(), "to": to.isoformat()})

        col1, col2, col3, col4 = st.columns(4)
        with col1:
            st.metric(t("progress.completion"), f"{prog['summary']['completionRate']*100:.0f}%")
        with col2:
            st.metric(t("progress.xp"), prog["reward"]["xp"])
        with col3:
            st.metric(t("progress.level"), prog["reward"]["level"])
        with col4:
            st.metric(t("progress.streak"), prog["reward"]["streak"])

        daily = prog.get("daily", [])
        if daily:
            df = pd.DataFrame(daily)
            df["date"] = pd.to_datetime(df["date"])
            df = df.sort_values("date")
            st.subheader(t("progress.trend"))
            st.bar_chart(df.set_index("date")[["done_count"]])
            st.subheader(t("progress.time"))
            st.bar_chart(df.set_index("date")[["spent_minutes"]])
        else:
            st.info(t("progress.empty"))

elif page == "settings":
    st.header(t("settings.header"))
    style = st.selectbox(
        t("settings.style"),
        ["gentle", "strict", "mentor"],
        index=["gentle", "strict", "mentor"].index(st.session_state.style),
        format_func=lambda x: t(f"style.{x}"),
    )
    st.session_state.style = style
    st.write(t("settings.saved"))
    st.caption(fmt("settings.backend", backend_url=BACKEND_URL))
