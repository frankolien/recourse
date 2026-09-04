"use client";

import { useEffect, useId, useState, useSyncExternalStore } from "react";
import type { KeyboardEvent } from "react";

const slides = [
  {
    title: "Two keys sign, one of them is yours",
    text: "Your phone's Secure Enclave and your iCloud key sign together. Neither leaves the device that holds it.",
  },
  {
    title: "Lose the phone, keep the money",
    text: "A sealed recovery key and your cloud key bring the account back on a new phone. Nothing to write down.",
  },
  {
    title: "No single key we hold can spend",
    text: "The account is a 2-of-3 smart account on Arc. The chain enforces it, not us.",
  },
];

const ROTATE_MS = 5000;
const REDUCED_MOTION = "(prefers-reduced-motion: reduce)";

function subscribe(onChange: () => void) {
  const query = window.matchMedia(REDUCED_MOTION);
  query.addEventListener("change", onChange);
  return () => query.removeEventListener("change", onChange);
}

function getSnapshot() {
  return window.matchMedia(REDUCED_MOTION).matches;
}

// Until the client hydrates, behave as if motion is reduced so nothing rotates
// before the user's preference has been read.
function getServerSnapshot() {
  return true;
}

export function SecurityCarousel() {
  const [index, setIndex] = useState(0);
  const reducedMotion = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
  const baseId = useId();

  useEffect(() => {
    if (reducedMotion) return;
    const id = window.setInterval(() => {
      setIndex((current) => (current + 1) % slides.length);
    }, ROTATE_MS);
    return () => window.clearInterval(id);
  }, [reducedMotion, index]);

  function select(next: number) {
    const wrapped = (next + slides.length) % slides.length;
    setIndex(wrapped);
    document.getElementById(`${baseId}-tab-${wrapped}`)?.focus();
  }

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "ArrowRight") select(index + 1);
    else if (event.key === "ArrowLeft") select(index - 1);
    else if (event.key === "Home") select(0);
    else if (event.key === "End") select(slides.length - 1);
    else return;
    event.preventDefault();
  }

  const slide = slides[index];

  return (
    <div className="site-carousel">
      <div className="site-carousel-bars" role="tablist" aria-label="How the account is secured" onKeyDown={onKeyDown}>
        {slides.map((item, i) => {
          const active = i === index;
          return (
            <button
              key={item.title}
              type="button"
              role="tab"
              id={`${baseId}-tab-${i}`}
              aria-selected={active}
              aria-controls={`${baseId}-panel`}
              tabIndex={active ? 0 : -1}
              className={active ? "site-carousel-bar is-active" : "site-carousel-bar"}
              onClick={() => setIndex(i)}
            >
              <span className="site-carousel-track">
                <span className={reducedMotion ? "site-carousel-fill is-static" : "site-carousel-fill"} />
              </span>
              <span className="site-visually-hidden">{item.title}</span>
            </button>
          );
        })}
      </div>
      <div className="site-carousel-slide" role="tabpanel" id={`${baseId}-panel`} aria-labelledby={`${baseId}-tab-${index}`}>
        <h3 key={slide.title} className="site-h3">
          {slide.title}
        </h3>
        <p key={slide.text}>{slide.text}</p>
      </div>
    </div>
  );
}
