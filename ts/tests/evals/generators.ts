/**
 * Deterministic context generators for evaluation benchmarks.
 *
 * All generators use seeded pseudo-random for reproducibility.
 */

/** Simple seeded PRNG (mulberry32) for deterministic generation */
function createRng(seed: number) {
  let s = seed | 0;
  return () => {
    s = (s + 0x6d2b79f5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// --- Needle-in-a-Haystack ---

const FILLER_WORDS = [
  "the",
  "quick",
  "brown",
  "fox",
  "jumps",
  "over",
  "lazy",
  "dog",
  "alpha",
  "beta",
  "gamma",
  "delta",
  "epsilon",
  "zeta",
  "eta",
  "theta",
  "information",
  "processing",
  "system",
  "network",
  "protocol",
  "interface",
  "analysis",
  "computation",
  "algorithm",
  "structure",
  "function",
  "variable",
  "document",
  "reference",
  "chapter",
  "section",
  "paragraph",
  "sentence",
];

function generateFillerText(rng: () => number, targetLength: number): string {
  const parts: string[] = [];
  let length = 0;
  while (length < targetLength) {
    // Generate a "sentence" of 5-15 words
    const sentenceLen = 5 + Math.floor(rng() * 11);
    const words: string[] = [];
    for (let i = 0; i < sentenceLen; i++) {
      words.push(FILLER_WORDS[Math.floor(rng() * FILLER_WORDS.length)]);
    }
    words[0] = words[0].charAt(0).toUpperCase() + words[0].slice(1);
    const sentence = words.join(" ") + ". ";
    parts.push(sentence);
    length += sentence.length;
  }
  return parts.join("").slice(0, targetLength);
}

export type HaystackOptions = {
  size: number;
  needle: string;
  /** Position as fraction 0-1. Default: 0.5 (middle). Use -1 for random. */
  needlePosition?: number;
  seed?: number;
};

/**
 * Generates a haystack string of `size` characters with a needle hidden inside.
 * Returns both the haystack and the exact position of the needle.
 */
export function generateHaystack(options: HaystackOptions): {
  haystack: string;
  needlePosition: number;
} {
  const { size, needle, seed = 42 } = options;
  const rng = createRng(seed);

  let pos: number;
  if (options.needlePosition === -1) {
    pos = Math.floor(rng() * (size - needle.length));
  } else {
    const frac = options.needlePosition ?? 0.5;
    pos = Math.floor(frac * (size - needle.length));
  }

  // Generate filler, then splice in the needle
  const filler = generateFillerText(rng, size);
  const haystack =
    filler.slice(0, pos) + needle + filler.slice(pos + needle.length);

  return { haystack: haystack.slice(0, size), needlePosition: pos };
}

// --- Person Records ---

const FIRST_NAMES = [
  "Alice",
  "Bob",
  "Charlie",
  "Diana",
  "Eve",
  "Frank",
  "Grace",
  "Henry",
  "Iris",
  "Jack",
  "Kate",
  "Leo",
  "Mia",
  "Noah",
  "Olivia",
  "Paul",
  "Quinn",
  "Ruby",
  "Sam",
  "Tara",
  "Uma",
  "Vic",
  "Wendy",
  "Xander",
];

const CITIES = [
  "Paris",
  "London",
  "Tokyo",
  "Berlin",
  "Rome",
  "Madrid",
  "Oslo",
  "Seoul",
  "Cairo",
  "Lima",
  "Dubai",
  "Mumbai",
  "Sydney",
  "Toronto",
];

const COLORS = [
  "red",
  "blue",
  "green",
  "yellow",
  "purple",
  "orange",
  "teal",
  "indigo",
];

export type PersonRecord = {
  id: number;
  name: string;
  age: number;
  city: string;
  favoriteColor: string;
};

/**
 * Generates N deterministic person records.
 * Ages range from 18-80. Cities and colors are distributed across the set.
 */
export function generatePersonRecords(
  count: number,
  seed = 42,
): PersonRecord[] {
  const rng = createRng(seed);
  const records: PersonRecord[] = [];
  for (let i = 0; i < count; i++) {
    records.push({
      id: i + 1,
      name: FIRST_NAMES[Math.floor(rng() * FIRST_NAMES.length)] + "_" + (i + 1),
      age: 18 + Math.floor(rng() * 63),
      city: CITIES[Math.floor(rng() * CITIES.length)],
      favoriteColor: COLORS[Math.floor(rng() * COLORS.length)],
    });
  }
  return records;
}

/**
 * Pre-computes expected answers for person record queries.
 */
export function computePersonAnswers(records: PersonRecord[]) {
  const olderThan30 = records.filter((r) => r.age > 30).length;

  // Group by city for pair matching
  const byCity: Record<string, PersonRecord[]> = {};
  for (const r of records) {
    (byCity[r.city] ??= []).push(r);
  }
  let pairAgeSum = 0;
  let pairCount = 0;
  for (const group of Object.values(byCity)) {
    for (let i = 0; i < group.length; i++) {
      for (let j = i + 1; j < group.length; j++) {
        pairAgeSum += group[i].age + group[j].age;
        pairCount++;
      }
    }
  }

  return { olderThan30, pairAgeSum, pairCount };
}

// --- Multi-hop Documents ---

export type MultiHopDocument = {
  id: number;
  name: string;
  city?: string;
  favoriteColor?: string;
  occupation?: string;
};

export type MultiHopDataset = {
  documents: MultiHopDocument[];
  /** The target person whose color we're asking about */
  targetCity: string;
  targetName: string;
  expectedAnswer: string;
};

/**
 * Generates a multi-hop dataset where:
 * - One document has {name, city} (the link)
 * - Another document has {name, favoriteColor} (the answer)
 * - Many distractor documents fill the space
 *
 * Query: "What is the favorite color of the person who lives in {targetCity}?"
 * Requires: find person by city → look up their color
 */
export function generateMultihopDocuments(
  distractorCount: number,
  seed = 42,
): MultiHopDataset {
  const rng = createRng(seed);

  const targetName = "TargetPerson";
  const targetCity = "Atlantis"; // Unique city not in CITIES
  const targetColor = "crimson"; // Unique color not in COLORS

  const documents: MultiHopDocument[] = [];

  // Add distractors first
  for (let i = 0; i < distractorCount; i++) {
    documents.push({
      id: i + 1,
      name: FIRST_NAMES[Math.floor(rng() * FIRST_NAMES.length)] + "_d" + i,
      city: CITIES[Math.floor(rng() * CITIES.length)],
      favoriteColor: COLORS[Math.floor(rng() * COLORS.length)],
      occupation: ["engineer", "teacher", "doctor", "artist"][
        Math.floor(rng() * 4)
      ],
    });
  }

  // Insert the two target documents at random positions
  const pos1 = Math.floor(rng() * (documents.length + 1));
  documents.splice(pos1, 0, {
    id: distractorCount + 1,
    name: targetName,
    city: targetCity,
  });

  const pos2 = Math.floor(rng() * (documents.length + 1));
  documents.splice(pos2, 0, {
    id: distractorCount + 2,
    name: targetName,
    favoriteColor: targetColor,
  });

  return {
    documents,
    targetCity,
    targetName,
    expectedAnswer: targetColor,
  };
}

// --- OOLONG-style Semantic Classification ---

/**
 * Question bank organized by TREC coarse categories.
 * Each question requires reading comprehension to classify — no keyword shortcuts.
 */
const TREC_QUESTIONS: Record<string, string[]> = {
  entity: [
    "What is the largest ocean on Earth?",
    "What instrument did Miles Davis play?",
    "What currency is used in Japan?",
    "What language has the most native speakers?",
    "What planet is known as the Red Planet?",
    "What is the chemical symbol for gold?",
    "What gemstone is the hardest natural substance?",
    "What vitamin is produced when skin is exposed to sunlight?",
    "What gas makes up most of Earth's atmosphere?",
    "What bone is the longest in the human body?",
    "What animal is the fastest on land?",
    "What metal is liquid at room temperature?",
    "What organ is responsible for filtering blood?",
    "What fabric is made from silkworm cocoons?",
    "What tree produces acorns?",
    "What sport uses a shuttlecock?",
    "What flower is associated with the Netherlands?",
    "What element has the atomic number 1?",
    "What constellation contains the North Star?",
    "What rock type is formed from cooled lava?",
    "What disease is caused by a deficiency of vitamin C?",
    "What particle carries a positive charge?",
    "What alloy is made of copper and tin?",
    "What grain is used to make sake?",
    "What pigment makes plants green?",
    "What breed of dog is known for rescuing people in the Alps?",
    "What type of cloud produces thunderstorms?",
    "What unit measures electrical resistance?",
    "What acid is found in vinegar?",
    "What mineral is table salt made from?",
  ],
  "human being": [
    "Who painted the Mona Lisa?",
    "Who was the first person to walk on the moon?",
    "Who wrote Romeo and Juliet?",
    "Who discovered penicillin?",
    "Who was the first female Prime Minister of the United Kingdom?",
    "Who developed the theory of general relativity?",
    "Who composed the Four Seasons?",
    "Who is credited with inventing the printing press?",
    "Who was the first Emperor of Rome?",
    "Who directed the movie Psycho?",
    "Who won the Nobel Peace Prize in 1964?",
    "Who founded Microsoft alongside Bill Gates?",
    "Who sailed across the Atlantic in 1492?",
    "Who wrote the Communist Manifesto with Friedrich Engels?",
    "Who is known as the father of modern philosophy?",
    "Who was the youngest president of the United States?",
    "Who choreographed The Nutcracker ballet?",
    "Who built the first successful airplane?",
    "Who translated the Bible into German?",
    "Who was the lead singer of Queen?",
    "Who is the author of A Brief History of Time?",
    "Who designed the Eiffel Tower?",
    "Who established the nursing profession during the Crimean War?",
    "Who painted The Starry Night?",
    "Who was the first woman to fly solo across the Atlantic?",
    "Who invented the telephone?",
    "Who was the last pharaoh of ancient Egypt?",
    "Who formulated the laws of motion?",
    "Who wrote Pride and Prejudice?",
    "Who created the periodic table of elements?",
  ],
  "numeric value": [
    "How many chromosomes do humans have?",
    "How many rings are on the Olympic flag?",
    "How many bones are in the adult human body?",
    "How many planets are in our solar system?",
    "What year did the Berlin Wall fall?",
    "How many strings does a standard guitar have?",
    "What is the boiling point of water in Fahrenheit?",
    "How many teeth does an adult human typically have?",
    "What year was the United Nations founded?",
    "How many amendments are in the US Bill of Rights?",
    "How many days does Mercury take to orbit the Sun?",
    "What is the speed of light in kilometers per second?",
    "How many symphonies did Beethoven compose?",
    "What year did World War I begin?",
    "How many elements are in the periodic table?",
    "What percentage of the Earth's surface is covered by water?",
    "How many squares are on a chess board?",
    "What year was the first email sent?",
    "How many cards are in a standard deck?",
    "How many moons does Jupiter have?",
    "What is the freezing point of water in Celsius?",
    "How many keys are on a standard piano?",
    "How many time zones does Russia span?",
    "What year was the Magna Carta signed?",
    "How many players are on a soccer team?",
    "What is the atomic number of carbon?",
    "How many continents are there?",
    "What year did the Titanic sink?",
    "How many lines are in a sonnet?",
    "How many vertices does a cube have?",
  ],
  location: [
    "Where is the Great Barrier Reef located?",
    "Where was the first Olympic Games held?",
    "Where is Machu Picchu situated?",
    "In what country would you find the Serengeti?",
    "Where is the headquarters of the United Nations?",
    "What city is home to the Colosseum?",
    "Where does the Amazon River empty into?",
    "In which country is Mount Kilimanjaro?",
    "Where is the Louvre museum?",
    "What country has the longest coastline?",
    "Where is the Taj Mahal located?",
    "In which city was the Declaration of Independence signed?",
    "Where is Lake Baikal?",
    "What country is home to Angkor Wat?",
    "Where was paper first invented?",
    "In which ocean is Madagascar?",
    "Where is the Parthenon?",
    "What city is known as the Venice of the East?",
    "Where is the world's driest desert?",
    "In which country is the Giant's Causeway?",
    "Where does the Danube River begin?",
    "What country is home to the fjords?",
    "Where was democracy first practiced?",
    "In which city is the Sagrada Familia?",
    "Where is the Panama Canal?",
    "What country is the Sahara Desert primarily in?",
    "Where is Silicon Valley?",
    "In which country are the Galápagos Islands?",
    "Where is the Brandenburg Gate?",
    "What city hosted the 2008 Summer Olympics?",
  ],
  description: [
    "What causes tides in the ocean?",
    "Why do leaves change color in autumn?",
    "How does a vaccine work?",
    "What is the process of photosynthesis?",
    "Why do we have seasons?",
    "How does encryption protect data?",
    "What is the greenhouse effect?",
    "Why do metals conduct electricity?",
    "How do antibiotics fight infections?",
    "What causes a rainbow to appear?",
    "Why does ice float on water?",
    "How does sonar work?",
    "What is the theory of natural selection?",
    "Why do some substances dissolve in water?",
    "How does a compass work?",
    "What is the role of mitochondria in a cell?",
    "Why does the moon have phases?",
    "How do earthquakes occur?",
    "What is the principle behind a lever?",
    "Why do stars twinkle?",
    "How does the human immune system work?",
    "What causes wind to blow?",
    "Why is the sky blue?",
    "How does a battery store energy?",
    "What is inflation in economics?",
    "Why do volcanoes erupt?",
    "How does GPS determine location?",
    "What is the Doppler effect?",
    "Why do we dream?",
    "How does natural gas form underground?",
  ],
  abbreviation: [
    "What does UNESCO stand for?",
    "What does DNA stand for?",
    "What is the full form of LASER?",
    "What does NATO stand for?",
    "What is the meaning of the abbreviation SCUBA?",
    "What does HTTP stand for?",
    "What is the full form of AIDS?",
    "What does OPEC stand for?",
    "What does FAQ stand for?",
    "What is the meaning of the acronym RADAR?",
    "What does JPEG stand for?",
    "What is the full form of ASAP?",
    "What does FIFA stand for?",
    "What is the meaning of PhD?",
    "What does CPU stand for?",
    "What is the full form of ATM?",
    "What does WHO stand for?",
    "What does GPS stand for?",
    "What is the full form of SOS?",
    "What does RSVP stand for?",
    "What does PDF stand for?",
    "What is the full form of MBA?",
    "What does UNICEF stand for?",
    "What does Wi-Fi stand for?",
    "What is the full form of CEO?",
    "What does PIN stand for?",
    "What does AWOL stand for?",
    "What is the full form of SWAT?",
    "What does ETA stand for?",
    "What does HTML stand for?",
  ],
};

const TREC_LABELS = Object.keys(TREC_QUESTIONS) as Array<
  keyof typeof TREC_QUESTIONS
>;

export type OolongEntry = {
  date: string;
  userId: number;
  instance: string;
  label: string; // ground truth, NOT included in the formatted string
};

export type OolongDataset = {
  /** Formatted string matching OOLONG format (no labels) */
  context: string;
  /** All entries with ground truth labels */
  entries: OolongEntry[];
  /** The query to ask */
  query: string;
  /** Expected numeric answer */
  expected: string;
  /** The target label being counted */
  targetLabel: string;
  /** User IDs selected for the query (empty = all) */
  targetUserIds: number[];
};

/**
 * Generates an OOLONG-style dataset: questions with implicit semantic categories.
 *
 * The model must READ each question to determine its TREC category.
 * `context.filter()` cannot solve this — it requires LLM judgment per item.
 *
 * @param entryCount Number of entries to generate
 * @param seed Random seed for reproducibility
 */
export function generateOolongDataset(
  entryCount: number,
  seed = 42,
): OolongDataset {
  const rng = createRng(seed);

  // Generate unique user IDs
  const userIdPool: number[] = [];
  for (let i = 0; i < Math.min(entryCount, 200); i++) {
    userIdPool.push(10000 + Math.floor(rng() * 90000));
  }

  const entries: OolongEntry[] = [];
  const months = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];

  for (let i = 0; i < entryCount; i++) {
    const label = TREC_LABELS[Math.floor(rng() * TREC_LABELS.length)];
    const questions = TREC_QUESTIONS[label];
    const question = questions[Math.floor(rng() * questions.length)];
    const userId = userIdPool[Math.floor(rng() * userIdPool.length)];
    const month = months[Math.floor(rng() * 12)];
    const day = 1 + Math.floor(rng() * 28);
    const year = 2022 + Math.floor(rng() * 3);

    entries.push({
      date: `${month} ${day}, ${year}`,
      userId,
      instance: question,
      label,
    });
  }

  // Format context string (same format as OOLONG — NO labels included)
  const lines = entries.map(
    (e) => `Date: ${e.date} || User: ${e.userId} || Instance: ${e.instance}`,
  );
  const context = lines.join("\n");

  // Pick a target label — always query ALL entries (no user ID filtering)
  // to keep query text identical across scales for clean scaling analysis.
  const targetLabel = TREC_LABELS[Math.floor(rng() * TREC_LABELS.length)];
  const targetUserIds: number[] = [];

  const expectedCount = entries.filter((e) => e.label === targetLabel).length;

  const query = `Among all instances, how many data points should be classified as label '${targetLabel}'? Each instance is a question that can be semantically classified into one of these categories: entity, human being, numeric value, location, description, abbreviation. The data does NOT provide labels — you must determine the category of each question by reading it. Return only the number.`;

  return {
    context,
    entries,
    query,
    expected: String(expectedCount),
    targetLabel,
    targetUserIds,
  };
}
