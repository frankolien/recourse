"use client";

import { useEffect, useRef, useState } from "react";
import { GOOGLE_CLIENT_ID } from "@/lib/session";

// Minimal typing for the Google Identity Services global we use.
interface GoogleIdentity {
  accounts: {
    id: {
      initialize: (config: { client_id: string; callback: (response: { credential?: string }) => void }) => void;
      renderButton: (parent: HTMLElement, options: Record<string, unknown>) => void;
    };
  };
}
declare global {
  interface Window {
    google?: { accounts?: GoogleIdentity["accounts"] };
  }
}

const GSI_SRC = "https://accounts.google.com/gsi/client";

// Renders Google's official sign-in button. On success it hands back the ID token
// (credential); the caller exchanges it with the backend. Falls back to a clear disabled
// state when NEXT_PUBLIC_GOOGLE_CLIENT_ID is not configured.
export function GoogleSignInButton({
  onCredential,
  onError,
}: {
  onCredential: (idToken: string) => void;
  onError?: (message: string) => void;
}) {
  const slot = useRef<HTMLDivElement>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (!GOOGLE_CLIENT_ID) return;
    let cancelled = false;

    function render() {
      if (cancelled || !window.google?.accounts?.id || !slot.current) return;
      window.google.accounts.id.initialize({
        client_id: GOOGLE_CLIENT_ID,
        callback: (response) => {
          if (response.credential) onCredential(response.credential);
          else onError?.("Google did not return a credential");
        },
      });
      slot.current.replaceChildren();
      window.google.accounts.id.renderButton(slot.current, {
        type: "standard",
        theme: "outline",
        size: "large",
        text: "continue_with",
        shape: "pill",
        logo_alignment: "center",
        width: 320,
      });
    }

    const existing = document.querySelector<HTMLScriptElement>(`script[src="${GSI_SRC}"]`);
    if (window.google?.accounts?.id) {
      render();
    } else if (existing) {
      existing.addEventListener("load", render);
    } else {
      const script = document.createElement("script");
      script.src = GSI_SRC;
      script.async = true;
      script.defer = true;
      script.onload = render;
      script.onerror = () => {
        if (!cancelled) setFailed(true);
      };
      document.head.appendChild(script);
    }
    return () => {
      cancelled = true;
    };
  }, [onCredential, onError]);

  if (!GOOGLE_CLIENT_ID) {
    return (
      <button className="auth-provider" type="button" disabled title="Set NEXT_PUBLIC_GOOGLE_CLIENT_ID to enable Google sign-in">
        Continue with Google (not configured)
      </button>
    );
  }
  if (failed) {
    return (
      <button className="auth-provider" type="button" disabled>
        Google sign-in unavailable
      </button>
    );
  }
  return <div ref={slot} className="google-signin-slot" />;
}
