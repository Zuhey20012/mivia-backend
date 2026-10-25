import type { MarkdownInstance } from "astro";
import { HELP_ARTICLES, helpPath, type HelpKey, type Lang } from "../i18n/routes";

type Frontmatter = { key: HelpKey; order: number; title: string; description: string };
type Article = MarkdownInstance<Frontmatter>;

const modules: Record<Lang, Record<string, Article>> = {
  fi: import.meta.glob<Article>("../content/help/fi/*.md", { eager: true }),
  en: import.meta.glob<Article>("../content/help/en/*.md", { eager: true }),
};

export type HelpArticle = Frontmatter & { path: string; Content: Article["Content"] };

/** Help articles of one language, in display order. Every key in HELP_ARTICLES must exist in both languages. */
export function helpArticles(lang: Lang): HelpArticle[] {
  const list = Object.values(modules[lang]).map((m) => ({
    ...m.frontmatter,
    path: helpPath(m.frontmatter.key, lang),
    Content: m.Content,
  }));
  for (const a of HELP_ARTICLES) {
    if (!list.some((x) => x.key === a.key)) throw new Error(`Help article "${a.key}" is missing in ${lang}`);
  }
  return list.sort((a, b) => a.order - b.order);
}

export function helpArticle(lang: Lang, key: HelpKey): HelpArticle {
  const a = helpArticles(lang).find((x) => x.key === key);
  if (!a) throw new Error(`Help article ${key} (${lang}) not found`);
  return a;
}
