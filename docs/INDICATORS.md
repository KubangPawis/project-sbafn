# INDICATORS.md

Practical reasoning, measurement, and QA for the features SBAFN uses to estimate **street-level flood‑proneness**. This file focuses on **street/terrain/network indicators**, which are the relatively stable attributes of a segment. Dynamic context (rainfall, incident reports) is referenced but documented elsewhere.

---

## 0) Scope & philosophy

- **What belongs here:** Physical roadside features, topographic context, and road‑network attributes that influence how water accumulates, drains, or moves across a street segment.
- **What doesn’t (but is used in the model):** **Rainfall intensity** and **news/advisory reports**. These are event/context layers, not persistent indicators. We summarize them and document full details in `METHODOLOGY.md`.
- **Why indicators matter:** They make scores **explainable**. Each indicator has a clear engineering rationale and a measurable proxy so planners can act on it (e.g., add inlets, regrade, clear canal access).

---

## 1) Naming conventions

- Features are normalized **per segment** and use consistent suffixes:
  - `*_cnt_30m` → count per 30 meters of segment length
  - `*_flag` → boolean 0/1 indicator
  - `_m`, `_pct`, `_cm` → physical units
- Examples: `inlet_cnt_30m`, `grate_cnt_30m`, `canal_dist_m`, `elev_rel_m`, `grade_pct`.

---

## 2) Indicators Table (Summary)

| Group | Feature | Unit / Scale | Expected relation to risk | Why it matters (intuition) |
|---|---|---|---|---|
| Physical | **Curb inlets** (`inlet_cnt_30m`) | count/30 m | **↑** more inlets ⇒ lower risk | Let curbside water escape into drains; too few ⇒ ponding. |
| Physical | **Drainage grates** (`grate_cnt_30m`) | count/30 m | **↑** more grates ⇒ lower risk | Let mid-lane water escape into drains; too few ⇒ ponding. |
| Physical | **Vegetation strips** (`veg_strip_flag`) | 0/1 | **↓** or **↑** context‑dependent | Vegetation/soil absorbs and slows runoff (good), but if blocking inlets can trap debris (bad). |
| Physical | **Open Canals** (`open_canal_flag`) | 0/1 | near/closer ⇒ higher risk | Close to open channels, streets are exposed to backflow during high river/tide stages |
| Topography | **Absolute elevation** (`elev_abs_m`) | m | **↓** lower elevation compared to receiving water body ⇒ higher risk | Low-lying segments relative to the receiving water body are more prone to backwater conditions. |
| Topography | **Relative elevation** (`elev_rel_m`) | m | **↓** lower than neighbors ⇒ higher risk | Being lower than neighboring streets creates a **bowl** that gathers runoff from surrounding slopes, increasing ponding. |
| Topography | **Road slope** (`grade_pct`) | % | near-zero street slope ⇒ higher risk | Flatter streets tend to pond; Steeper streets **shifting the problem downstream** to low nodes/streets. |
| Road network | **Road classification** (`highway`) | categorical | context-dependent | Proxy for design standards, traffic exposure, and drainage capacity. |
| Road network | **Road width (proxy)** (`lanes`) | lanes | **↑** wider ⇒ lower risk | More surface area implies higher runoff volume. |

> [!INFO]
> Arrows show general tendency; local conditions can override. Use **Explainability Panel** to see the top drivers for a specific segment.
