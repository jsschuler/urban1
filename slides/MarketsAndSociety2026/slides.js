window.SLIDES = [
  {
    "title": "Urbanization from the Bottom Up",
    "body": "Housing Markets, Endogenous Zoning, and Transport Access",
    "seconds": 20,
    "notes": "John S. Schuler · George Mason University. Markets and Society 2026.",
    "kind": "title",
    "author": [
      "John S. Schuler",
      "Department of Computational and Data Sciences",
      "George Mason University"
    ]
  },
  {
    "title": "Who Gets to Shape the City?",
    "body": "",
    "seconds": 35,
    "notes": "",
    "bullets": [
      "Households choose homes, but those choices change the environment valued by their neighbors.",
      "Incumbents can collectively restrict subsequent construction.",
      "The question: how does this feedback affect housing accommodation and urban form?"
    ]
  },
  {
    "title": "Three Margins of Adjustment",
    "body": "",
    "seconds": 30,
    "notes": "",
    "bullets": [
      "Housing: arrivals, vacancy search, incumbent moves, and construction.",
      "Institutions: conditional zoning rules adopted through incumbent voting.",
      "Accessibility: employment locations and a neighborhood transport network."
    ]
  },
  {
    "title": "The Experiment",
    "body": "",
    "seconds": 35,
    "notes": "",
    "bullets": [
      "Cross every zoning, horizon, and transport comparison with budget-based displacement off versus on.",
      "In each preset, displacement is matched between actual housing choices and the hypothetical zoning-vote branches.",
      "Hold other settings fixed; reset before each condition and repeat across seeds. Compare exclusion, sorting, and job access."
    ]
  },
  {
    "title": "Architecture · The City and its State",
    "body": "",
    "seconds": 35,
    "notes": "",
    "bullets": [
      "City → neighborhoods → buildings → individual dwellings and occupants.",
      "Default geometry: <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mn>10</mn><mo>×</mo><mn>10</mn></math> neighborhoods; <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mn>8</mn><mo>×</mo><mn>8</mn></math> building sites per neighborhood.",
      "Building height is the number of stacked dwellings; a vacant dwelling remains part of the stock.",
      "The city also stores agents, neighborhood laws, employers, and transport links."
    ]
  },
  {
    "title": "Heterogeneity Is Central",
    "body": "",
    "seconds": 35,
    "notes": "",
    "bullets": [
      "Each agent has a home, job location, budget, and preference parameters.",
      "Neighborhood preferences cover median, maximum, and minimum building height.",
      "Building-height preference and commute tolerance distinguish otherwise similar households.",
      "Floored normal draws generate preferred heights; log-normal draws generate budgets and tolerances."
    ]
  },
  {
    "title": "Residential Utility",
    "body": "",
    "seconds": 45,
    "notes": "Neighborhood median building height is the implemented density proxy. Explain the five marginal transforms and their aggregation; do not identify copula dependence with correlation between household draws. The appendix states the numerical floors used in the marginal transforms.",
    "bullets": [
      "Five marginal utilities score commute distance, neighborhood median/maximum/minimum height, and building height.",
      "Distance <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mi>d</mi></math> is measured in building units; <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><msub><mi>λ</mi><mi>i</mi></msub></math> controls commute tolerance.",
      "For built form, <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><msub><mi>δ</mi><mi>i</mi></msub></math> is proportional deviation from the preferred value; larger <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><msub><mi>σ</mi><mi>i</mi></msub></math> means greater tolerance."
    ],
    "math": [
      "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"block\"><msub><mi>U</mi><mi>i</mi></msub><mo>=</mo><msub><mi>C</mi><msub><mi>θ</mi><mi>i</mi></msub></msub><mo stretchy=\"false\">(</mo><msub><mi>u</mi><mrow><mi>i</mi><mn>1</mn></mrow></msub><mo>,</mo><mo>…</mo><mo>,</mo><msub><mi>u</mi><mrow><mi>i</mi><mn>5</mn></mrow></msub><mo stretchy=\"false\">)</mo></math>",
      "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"block\"><msub><mi>u</mi><mtext>proximity</mtext></msub><mo>=</mo><mi>exp</mi><mo stretchy=\"false\">(</mo><mo>−</mo><mfrac><mrow><mi>d</mi></mrow><mrow><msub><mi>λ</mi><mi>i</mi></msub></mrow></mfrac><mo stretchy=\"false\">)</mo></math>",
      "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"block\"><msub><mi>u</mi><mtext>form</mtext></msub><mo>=</mo><mi>exp</mi><mo stretchy=\"false\">(</mo><mo>−</mo><mfrac><mrow><msup><msub><mi>δ</mi><mi>i</mi></msub><mn>2</mn></msup></mrow><mrow><mn>2</mn><msup><msub><mi>σ</mi><mi>i</mi></msub><mn>2</mn></msup></mrow></mfrac><mo stretchy=\"false\">)</mo></math>"
    ]
  },
  {
    "title": "What Is a Frank Copula?",
    "body": "",
    "seconds": 55,
    "notes": "Copulas separate dependence from marginal distributions. Here the copula is used as a utility aggregator; it does not generate correlated agent attributes.",
    "bullets": [
      "A copula is a joint distribution on <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><msup><mrow><mo>[</mo><mn>0</mn><mo>,</mo><mn>1</mn><mo>]</mo></mrow><mi>d</mi></msup></math> with uniform marginals; it describes dependence separately from marginal distributions.",
      "The Frank family is an Archimedean copula: one parameter <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mi>θ</mi></math> controls dependence. This five-dimensional model uses positive, agent-specific <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><msub><mi>θ</mi><mi>i</mi></msub></math>.",
      "Here the inputs are marginal utility scores, and the output is aggregate utility. As <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mi>θ</mi><mo>→</mo><mn>0</mn></math> the result approaches their product; as <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mi>θ</mi><mo>→</mo><mo>∞</mo></math> it approaches their minimum."
    ],
    "math": [
      "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"block\"><msub><mi>C</mi><mi>θ</mi></msub><mo stretchy=\"false\">(</mo><msub><mi>u</mi><mn>1</mn></msub><mo>,</mo><mo>…</mo><mo>,</mo><msub><mi>u</mi><mi>d</mi></msub><mo stretchy=\"false\">)</mo><mo>=</mo><mo>−</mo><mfrac><mrow><mn>1</mn></mrow><mrow><mi>θ</mi></mrow></mfrac><mi>log</mi><mo>[</mo><mn>1</mn><mo>+</mo><mfrac><mrow><munderover><mo>∏</mo><mrow><mi>j</mi><mo>=</mo><mn>1</mn></mrow><mi>d</mi></munderover><mo stretchy=\"false\">(</mo><msup><mi>e</mi><mrow><mo>−</mo><mi>θ</mi><msub><mi>u</mi><mi>j</mi></msub></mrow></msup><mo>−</mo><mn>1</mn><mo stretchy=\"false\">)</mo></mrow><mrow><msup><mrow><mo stretchy=\"false\">(</mo><msup><mi>e</mi><mrow><mo>−</mo><mi>θ</mi></mrow></msup><mo>−</mo><mn>1</mn><mo stretchy=\"false\">)</mo></mrow><mrow><mi>d</mi><mo>−</mo><mn>1</mn></mrow></msup></mrow></mfrac><mo>]</mo></math>"
    ],
    "source": {
      "title": "Archimedean Copulas · SAS Documentation",
      "url": "https://support.sas.com/documentation/cdl/en/etsug/67525/HTML/default/etsug_copula_details09.htm"
    }
  },
  {
    "title": "Search, Allocation, Construction",
    "body": "",
    "seconds": 40,
    "notes": "Distinguish a simulated search market from a calibrated equilibrium price model. Budget enters the displacement eligibility rule; this is a priority mechanism rather than a market-clearing price or rent process. With displacement off, budget does not enter utility or construction eligibility.",
    "bullets": [
      "Sample existing dwellings; choose the best available option if it improves utility.",
      "With displacement enabled, a higher-budget agent can take an occupied dwelling.",
      "An unhoused agent unable to move can add a dwelling at an allowed building site.",
      "Budgets confer displacement priority; the model does not determine market-clearing prices or rents."
    ]
  },
  {
    "title": "Architecture · One Simulation Step",
    "body": "",
    "seconds": 35,
    "notes": "",
    "bullets": [
      "At scheduled intervals: evaluate network expansion and proposed zoning rules.",
      "Process all unhoused agents and a sampled share of housed incumbent movers.",
      "Add new households, then process their housing choices.",
      "Assign new workers and evaluate employer relocation when enabled; publish statistics and geometry."
    ]
  },
  {
    "title": "Zoning Is Endogenous",
    "body": "",
    "seconds": 40,
    "notes": "",
    "bullets": [
      "Each neighborhood can accumulate conditional rules represented as decision trees.",
      "Tree nodes test median height, maximum height, minimum height, or vacancy.",
      "Leaves permit or prohibit new construction under the current local state.",
      "Rules constrain new supply; they do not delete the existing housing stock."
    ]
  },
  {
    "title": "Incumbents Compare Futures",
    "body": "",
    "seconds": 50,
    "notes": "Branches start from identical random seeds, but evolving trajectories can consume draws differently; arrivals are not guaranteed to match. Voting utility uses the same effective-distance calculation as housing choice.",
    "bullets": [
      "Copy the city into with-proposal and without-proposal branches.",
      "Simulate <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mi>H</mi></math> ticks of hypothetical adjustment using matched random seeds.",
      "Compare the utilities of the original neighborhood incumbents across branches.",
      "Adopt the proposed law only when more than half prefer the with-law outcome."
    ]
  },
  {
    "title": "Whose Welfare Enters the Vote?",
    "body": "",
    "seconds": 35,
    "notes": "Frame this as the institutional distinction to investigate. Do not announce an empirical welfare result.",
    "bullets": [
      "The electorate is the set of incumbent neighborhood residents.",
      "Prospective entrants can affect simulated futures but do not join the original electorate.",
      "Baseline voting branches hold incumbent mobility and construction off.",
      "This separates the interests represented in local choice from citywide housing accommodation."
    ]
  },
  {
    "title": "Experiment 1 · Zoning",
    "body": "",
    "seconds": 35,
    "notes": "Run each condition from an empty city. Live runs are illustrative; use tonight’s replicated results for inference.",
    "bullets": [
      "Run four conditions: zoning off/on, each with budget-based displacement off/on.",
      "Within each displacement regime, hold household inflow, preferences, transport, horizon, and employer settings fixed.",
      "Compare exclusion, residential sorting, and job access; test whether zoning’s effect depends on displacement."
    ]
  },
  {
    "title": "Zoning · Across Displacement Regimes",
    "body": "Short-horizon zoning: little exclusion change; more sorting with displacement.",
    "seconds": 40,
    "notes": "At tick 250 with displacement, Q1 exclusion is 14.74% with zoning versus 14.10% without; sorting is 0.139 versus 0.130. Without displacement, both conditions house everyone. This does not support a general claim that zoning raises exclusion. Three completed seeds; 250 ticks. Lines are seed means and shading is min–max, not a confidence interval. Displacement off above; on below. Q1/Q5 use fixed baseline budget thresholds. Arrivals are unmatched; baselines are reused. Sorting and commute describe housed residents only. Exact values and contrasts are in ANALYSIS.md.",
    "chart": "zoning"
  },
  {
    "title": "On Request · Zoning Disabled",
    "body": "",
    "seconds": 100,
    "notes": "Optional audience demonstration. Present the saved comparison first; run any preset if requested. Reset while idle between conditions. Live runs have unmatched arrivals and do not reproduce a saved seed. Reset while idle, then start. Switch to Blender. Return to the slide for metrics; let the 250-tick batch complete while continuing the explanation. Each comparison is repeated under both displacement regimes. Do not promise to finish every cell live; use prepared runs to cover the full design.",
    "demo": "no_zoning",
    "bullets": [
      "Start from an empty city with zoning proposals disabled.",
      "Watch where new dwellings accumulate and whether households remain unhoused.",
      "Each preset runs 250 ticks; inspect the trajectory as it develops.",
      "Select the displacement-off or displacement-on variant explicitly; reset between conditions."
    ]
  },
  {
    "title": "On Request · Zoning Enabled",
    "body": "",
    "seconds": 100,
    "notes": "Optional audience demonstration. Present the saved comparison first; run any preset if requested. Reset while idle between conditions. Live runs have unmatched arrivals and do not reproduce a saved seed. Reset while idle, then start. Switch to Blender. Avoid treating a single realization as the estimated treatment effect. Each comparison is repeated under both displacement regimes. Do not promise to finish every cell live; use prepared runs to cover the full design.",
    "demo": "zoning",
    "bullets": [
      "Reset to an empty city and enable local voting with <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mi>H</mi><mo>=</mo><mn>5</mn></math>.",
      "Inspect adopted laws and subsequent construction in Blender.",
      "Compare with the previous trajectory; use replicated results for inference.",
      "Select the displacement-off or displacement-on variant explicitly; reset between conditions."
    ]
  },
  {
    "title": "Experiment 2 · The Voting Horizon",
    "body": "",
    "seconds": 40,
    "notes": "",
    "bullets": [
      "Hold proposal frequency fixed while changing <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mi>H</mi></math> from 5 to 20.",
      "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mi>H</mi></math> is the duration of the hypothetical futures used in each vote.",
      "Longer anticipation can change both preferred rules and subsequent residential sorting.",
      "Repeat the short-versus-long comparison with displacement off and with displacement on."
    ]
  },
  {
    "title": "Horizons · Across Displacement Regimes",
    "body": "Long horizons: exclusion varies across seeds; sorting rises with displacement.",
    "seconds": 40,
    "notes": "Without displacement, H=20 yields Q1 exclusion of 0%, 0%, and 30.37% at tick 250, versus zero under H=5. The mean is 10.12%, driven by one run. With displacement, sorting rises from 0.139 to 0.158; Q1 exclusion falls slightly from 14.74% to 13.91%. Three completed seeds; 250 ticks. Lines are seed means and shading is min–max, not a confidence interval. Displacement off above; on below. Q1/Q5 use fixed baseline budget thresholds. Arrivals are unmatched; baselines are reused. Sorting and commute describe housed residents only. Exact values and contrasts are in ANALYSIS.md.",
    "chart": "horizons"
  },
  {
    "title": "On Request · Short versus Long Horizons",
    "body": "",
    "seconds": 130,
    "notes": "Optional audience demonstration. Present the saved comparison first; run any preset if requested. Reset while idle between conditions. Live runs have unmatched arrivals and do not reproduce a saved seed. Run the short condition, stop if needed, reset after idle, then run the long condition. Switch to Blender for each. Branch simulation may dominate runtime. Each comparison is repeated under both displacement regimes. Do not promise to finish every cell live; use prepared runs to cover the full design.",
    "demo": "horizons",
    "bullets": [
      "Load the short-horizon preset, reset, and run; repeat with the long-horizon preset.",
      "Use the experiment panel to try an audience-suggested horizon.",
      "Inspect law adoption and housing accommodation; longer branch simulations take more time.",
      "Select the displacement-off or displacement-on variant explicitly; reset between conditions."
    ]
  },
  {
    "title": "Longer Runs · Effects Depend on the Regime",
    "body": "At 1,000 ticks, H=20 without displacement spans 0–84% Q1 exclusion across five seeds.",
    "seconds": 40,
    "notes": "Central setting: 10×10 neighborhoods, 40 arrivals/tick; all 200 runs across its 40 cells completed. Figure selects four conditions, five seeds each, under both displacement regimes. Whiskers are full seed ranges, not confidence intervals. Without displacement, H=20 mean Q1 exclusion is 33.34%, range 0–84.11%; H=5 has zero exclusion. With displacement, sorting rises from 0.114 at H=5 to 0.161 at H=20. Roads reduce Q1 commute to about 8 units in both regimes. These are separate 1,000-tick runs, not extensions of the three-seed presentation trajectories. The full broad sweep completed 1,423/1,800 runs; partial runs are excluded.",
    "chart": "long_run"
  },
  {
    "title": "Experiment 3 · Transport Access",
    "body": "",
    "seconds": 40,
    "notes": "",
    "bullets": [
      "Jobs create a spatial anchor for residential utility.",
      "Network links connect neighborhood centers and change effective commuting distance.",
      "Keep employer behavior fixed across the transport comparison.",
      "Repeat the transport-off/on comparison in both displacement regimes."
    ]
  },
  {
    "title": "The Transport Mechanism",
    "body": "",
    "seconds": 45,
    "notes": "Road links are added by the model’s network procedure. Describe this as the implemented mechanism, not an estimated infrastructure policy. At the default grid spacing, adjacent neighborhood centers are eight building-site units apart; a direct network hop costs 1.01 before access travel. Voting and housing choice now use the same network-adjusted distance.",
    "bullets": [
      "Travel distance is the minimum of direct travel and access + network hops + destination access.",
      "The city caches shortest hop counts between neighborhood centers.",
      "An enabled employer starts centrally, assigns new workers, and evaluates alternative locations.",
      "Employer candidates are compared by mean effective commute after hypothetical adjustment."
    ]
  },
  {
    "title": "Transport · Across Displacement Regimes",
    "body": "Transport shortens commutes in both regimes; low-budget exclusion persists.",
    "seconds": 40,
    "notes": "At tick 250, roads reduce Q1 mean commute from 30.30 to 19.96 without displacement and from 12.47 to 6.02 with displacement. With displacement, Q1 exclusion remains about 15%. Q5 commute falls from 20.25 to 8.42. Transport does not eliminate budget-based exclusion. Three completed seeds; 250 ticks. Lines are seed means and shading is min–max, not a confidence interval. Displacement off above; on below. Q1/Q5 use fixed baseline budget thresholds. Arrivals are unmatched; baselines are reused. Sorting and commute describe housed residents only. Exact values and contrasts are in ANALYSIS.md.",
    "chart": "transport"
  },
  {
    "title": "On Request · Transport Off versus On",
    "body": "",
    "seconds": 130,
    "notes": "Optional audience demonstration. Present the saved comparison first; run any preset if requested. Reset while idle between conditions. Live runs have unmatched arrivals and do not reproduce a saved seed. Run both conditions from empty cities. Employer settings are fixed across the pair. Switch to Blender; distinguish road construction from employment relocation. Each comparison is repeated under both displacement regimes. Do not promise to finish every cell live; use prepared runs to cover the full design.",
    "demo": "transport",
    "bullets": [
      "Reset between transport-off and transport-on conditions.",
      "Hold zoning, horizon, household inflow, and employer settings fixed.",
      "Inspect network links in Blender; ask whether development follows improved access.",
      "Select the displacement-off or displacement-on variant explicitly; reset between conditions."
    ]
  },
  {
    "title": "Institutions Interact",
    "body": "",
    "seconds": 40,
    "notes": "These statements describe the central experimental setting, not calibrated real-city effects. The broader incomplete grid and conditional contrasts are documented in ANALYSIS.md.",
    "bullets": [
      "With displacement, zoning and longer voting horizons increase residential sorting in the central comparisons.",
      "Without displacement, long horizons can produce severe exclusion, with large variation across seeds.",
      "Transport lowers effective commuting distance in both regimes, but low-budget exclusion persists with displacement."
    ]
  },
  {
    "title": "Architecture · One Model, Two Interfaces",
    "body": "",
    "seconds": 40,
    "notes": "These runs alone do not establish causal effects in real cities or calibrated welfare magnitudes.",
    "bullets": [
      "Julia owns city state, household actions, law voting, employer behavior, and transport.",
      "The slides send run/reset/stop commands and receive aggregate statistics over a WebSocket.",
      "Blender receives city geometry and visualizes the same run over a separate WebSocket.",
      "Live visualization explains mechanisms; repeated runs supply the comparative evidence."
    ]
  },
  {
    "title": "Research Context · Spring 2026",
    "body": "",
    "seconds": 35,
    "notes": "Keep this historical context brief. No new comparison of AI products or capabilities is being asserted beyond the framing supplied for this talk.",
    "bullets": [
      "This model was developed in spring 2026, when AI coding tools were less advanced.",
      "The research question and economic mechanisms remain the focus of this talk.",
      "The implementation history provides context for the cost of building this research environment."
    ]
  },
  {
    "title": "AI-Assisted Implementation, Researcher-Led Design",
    "body": "",
    "seconds": 40,
    "notes": "Based on the spring talk. Mention Julia, browser controls, and Blender as the working research environment, not as the central contribution.",
    "bullets": [
      "The spring talk records roughly nine sessions with Claude.",
      "AI helped implement Julia routines, browser controls, WebSocket communication, and Blender geometry.",
      "Model design, economic debugging, and interpretation required researcher judgment."
    ]
  },
  {
    "title": "Exclusion, Sorting, and Access",
    "body": "",
    "seconds": 35,
    "notes": "Budget thresholds are fixed at quintiles of the baseline log-normal distribution (log mean 1, log SD 0.5). Q1 is lowest; Q5 highest. Empty groups and groups without housed residents have missing observations, not zero commutes. These three charts are time series. A Gini does not measure geographic contiguity; use neighborhood maps to inspect clustering.",
    "bullets": [
      "Housing exclusion: the unhoused share in each baseline budget quintile, including all agents in the denominator.",
      "Residential sorting: the population-weighted Gini of neighborhood mean budgets, among housed agents.",
      "Access to jobs: mean effective commute distance by budget quintile, among housed agents only.",
      "Read these together: apparently lower sorting or shorter commutes can coexist with greater exclusion. Total-wealth inequality remains a secondary measure."
    ]
  },
  {
    "title": "Housing Supply and its Rules Coevolve",
    "body": "",
    "seconds": 40,
    "notes": "Close on the housing-market research question. Invite questions after the 25-minute presentation.",
    "bullets": [
      "Housing exclusion depends on how allocation and local voting interact; zoning does not have one uniform effect.",
      "Long-horizon outcomes vary sharply across seeds without displacement.",
      "Transport improves access among housed residents; it does not eliminate exclusion.",
      "Read exclusion, sorting, and access together."
    ]
  },
  {
    "title": "Parameters · Geometry, Population, and Search",
    "body": "",
    "seconds": 0,
    "notes": "Optional parameter reference; outside the 25-minute talk budget.",
    "appendix": true,
    "table": {
      "headers": [
        "Parameter",
        "Preset Value",
        "Meaning"
      ],
      "rows": [
        [
          "City dimensions",
          "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mn>10</mn><mo>×</mo><mn>10</mn></math>",
          "Neighborhoods in the horizontal and vertical directions."
        ],
        [
          "Building sites per side <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mi>k</mi></math>",
          "8",
          "Each neighborhood contains <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><msup><mi>k</mi><mn>2</mn></msup></math> potential building sites."
        ],
        [
          "Initial population; random seed",
          "0; 42",
          "An empty city; seed for a fresh Julia process. Reset clears the city without reseeding."
        ],
        [
          "Ticks per batch",
          "250",
          "Actual number of simulation iterations requested by each preset."
        ],
        [
          "Arrivals per tick",
          "40",
          "Number of new agents added at each tick."
        ],
        [
          "Search intensity",
          "5",
          "Samples up to twice this many existing dwellings before evaluating available housing."
        ],
        [
          "Incumbent mover share",
          "0.10",
          "Fraction of housed incumbents selected to search; all unhoused incumbents also search."
        ],
        [
          "Budget-based displacement",
          "Off / On",
          "Crossed with every comparison. If enabled, a richer agent can take an occupied sampled dwelling."
        ]
      ]
    }
  },
  {
    "title": "Parameters · Household Distributions",
    "body": "Normal parameters refer to the underlying draw before flooring. Log-normal parameters refer to log values. Diagnostic budget quintiles use fixed baseline cutoffs (log mean 1, log SD 0.5), even if arrival-distribution parameters change.",
    "seconds": 0,
    "notes": "Optional parameter reference; outside the 25-minute talk budget.",
    "appendix": true,
    "table": {
      "headers": [
        "Household Attribute",
        "Mean / SD Parameters",
        "Distribution and Meaning"
      ],
      "rows": [
        [
          "Budget <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><msub><mi>b</mi><mi>i</mi></msub></math>",
          "1.0 / 0.5",
          "Log-normal; governs displacement priority and the wealth diagnostics."
        ],
        [
          "Preferred neighborhood median height",
          "3.0 / 2.0",
          "Normal draw, floored at 0.5; neighborhood density preference proxy."
        ],
        [
          "Preferred neighborhood maximum height",
          "6.0 / 2.0",
          "Normal draw, floored at 1.0."
        ],
        [
          "Preferred neighborhood minimum height",
          "1.0 / 1.0",
          "Normal draw, floored at 0.0."
        ],
        [
          "Preferred building height",
          "3.0 / 2.0",
          "Normal draw, floored at 0.5."
        ],
        [
          "Neighborhood tolerance",
          "−0.5 / 0.3",
          "Log-normal; applies to median, maximum, and minimum neighborhood height."
        ],
        [
          "Building tolerance",
          "−0.5 / 0.3",
          "Log-normal; applies to the chosen building’s height."
        ],
        [
          "Commute tolerance <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><msub><mi>λ</mi><mi>i</mi></msub></math>",
          "2.5 / 0.5",
          "Log-normal; distance decay scale in building units."
        ],
        [
          "Frank dependence <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><msub><mi>θ</mi><mi>i</mi></msub></math>",
          "0.7 / 0.4",
          "Log-normal; aggregates utility scores, not correlation between preference draws."
        ]
      ]
    },
    "math": [
      "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"block\"><mi>Z</mi><mo>∼</mo><mi>N</mi><mo stretchy=\"false\">(</mo><mn>0</mn><mo>,</mo><mn>1</mn><mo stretchy=\"false\">)</mo><mo>,</mo><mtext>    </mtext><mi>X</mi><mo>=</mo><mi>exp</mi><mo stretchy=\"false\">(</mo><mi>μ</mi><mo>+</mo><mi>σ</mi><mi>Z</mi><mo stretchy=\"false\">)</mo></math>"
    ]
  },
  {
    "title": "Parameters · Local Voting",
    "body": "",
    "seconds": 0,
    "notes": "Optional parameter reference; outside the 25-minute talk budget.",
    "appendix": true,
    "table": {
      "headers": [
        "Parameter",
        "Preset Value",
        "Meaning"
      ],
      "rows": [
        [
          "Proposal interval",
          "0 or 10 ticks",
          "Zero disables proposals. Otherwise proposals occur at tick 11, 21, … for interval 10."
        ],
        [
          "Voting horizon <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mi>H</mi></math>",
          "5 or 20 ticks",
          "Length of the hypothetical with-law and without-law futures."
        ],
        [
          "Displacement in voting branches",
          "Matches actual displacement",
          "Off/off or on/on in each preset; custom controls can explicitly separate them."
        ],
        [
          "Incumbent mover share in branches",
          "0",
          "Share of incumbent residents allowed to move in hypothetical futures."
        ],
        [
          "Incumbents may build in branches",
          "Off",
          "Whether incumbent movers may construct in hypothetical futures."
        ],
        [
          "Proposal rule structure",
          "Depth 2",
          "Random decision tree over median/max/min height and vacancy; random allow/prohibit leaves."
        ],
        [
          "Threshold spread",
          "25% of current level; minimum 0.25",
          "Threshold is a normal perturbation of the local observable, floored at zero."
        ],
        [
          "Adoption threshold",
          "Strict majority",
          "More than half of original neighborhood residents must prefer the with-law future."
        ]
      ]
    }
  },
  {
    "title": "Parameters · Transport and Employment",
    "body": "",
    "seconds": 0,
    "notes": "Optional parameter reference; outside the 25-minute talk budget.",
    "appendix": true,
    "table": {
      "headers": [
        "Parameter",
        "Preset Value",
        "Meaning"
      ],
      "rows": [
        [
          "Transport enabled",
          "Off / On",
          "Allows new links to be evaluated; switching off does not delete existing links."
        ],
        [
          "Transport evaluation interval",
          "20 ticks",
          "Evaluate expansion at tick 21, 41, … ."
        ],
        [
          "Distance per network hop",
          "1.01",
          "One network link costs 1.01 horizontal building-site units, plus home-to-center and center-to-job access."
        ],
        [
          "Employer enabled",
          "On",
          "Creates a central employer and assigns new arrivals as workers."
        ],
        [
          "Employer evaluation interval",
          "1 tick",
          "Frequency of location evaluation; zero fixes the existing employer location."
        ],
        [
          "Employer candidate locations",
          "5",
          "Number of sampled alternatives; current location is also considered."
        ],
        [
          "Employer horizon",
          "3 ticks",
          "Hypothetical adjustment before comparing mean worker commute."
        ]
      ]
    }
  },
  {
    "title": "Parameters · Utility and Display",
    "body": "",
    "seconds": 0,
    "notes": "Optional parameter reference; outside the 25-minute talk budget.",
    "appendix": true,
    "table": {
      "headers": [
        "Parameter",
        "Value",
        "Meaning"
      ],
      "rows": [
        [
          "Active utility dimensions",
          "All five",
          "Commute, median/max/min neighborhood height, and building height. Can be toggled through the Julia utility configuration."
        ],
        [
          "Preferred-value denominator floor",
          "0.5",
          "Avoids singular proportional deviations near a preferred value of zero."
        ],
        [
          "Commute scale floor",
          "0.1",
          "Lower bound used in the distance utility transform."
        ],
        [
          "Form-tolerance floor",
          "0.01",
          "Lower bound used in the height utility transform."
        ],
        [
          "Copula safeguards",
          "Small <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mi>θ</mi></math>: product; large <math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mi>θ</mi></math>: minimum",
          "Independence cutoff 0.000001; positive-dependence cutoff 50; marginal scores clipped away from endpoints by 0.000001."
        ],
        [
          "Blender update interval",
          "10 ticks",
          "Frequency of geometry updates; zero sends geometry only at batch end."
        ],
        [
          "Inter-tick delay",
          "0.1 seconds",
          "Pause between ticks; separate from computation time."
        ],
        [
          "Interface ports",
          "8765 / 8766",
          "Blender geometry / browser controls and statistics; fixed in the local presentation setup."
        ]
      ]
    },
    "math": [
      "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"block\"><msub><mi>δ</mi><mi>i</mi></msub><mo>=</mo><mfrac><mrow><mo>|</mo><mi>x</mi><mo>−</mo><msub><mi>x</mi><mtext>preferred</mtext></msub><mo>|</mo></mrow><mrow><mi>max</mi><mo stretchy=\"false\">(</mo><msub><mi>x</mi><mtext>preferred</mtext></msub><mo>,</mo><mn>0.5</mn><mo stretchy=\"false\">)</mo></mrow></mfrac></math>"
    ]
  }
];
