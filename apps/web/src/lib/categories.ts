export const CATEGORIES = [
  "Lebensmittel",
  "Miete",
  "Sparen/Investieren",
  "Drogerie",
  "Sport",
  "Freunde",
  "Geschenke",
  "Transport",
  "Abos",
  "Essen gehen",
  "Sonstiges",
  "Unkategorisiert",
] as const;

export type Category = (typeof CATEGORIES)[number];
