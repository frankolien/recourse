import type { ReactNode } from "react";
import "./site.css";
import { SiteNav } from "@/components/site/nav";
import { SiteFooter } from "@/components/site/footer";

export default function SiteLayout({ children }: { children: ReactNode }) {
  return (
    <div className="site-root">
      <a href="#site-main" className="site-skip">
        Skip to content
      </a>
      <SiteNav />
      <main id="site-main" className="site-main">
        {children}
      </main>
      <SiteFooter />
    </div>
  );
}
