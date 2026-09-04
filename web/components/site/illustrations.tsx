import Image from "next/image";
import { ArrowRight, Tag } from "lucide-react";

export function EarnCurve() {
  return (
    <div className="site-earn">
      <svg viewBox="0 0 320 150" className="site-earn-svg" aria-hidden="true" focusable="false">
        <defs>
          <linearGradient id="site-earn-fill" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0" stopColor="#3ecf8e" stopOpacity="0.35" />
            <stop offset="1" stopColor="#3ecf8e" stopOpacity="0" />
          </linearGradient>
        </defs>
        <path d="M0 134 C 110 134, 200 108, 258 62 C 288 38, 306 22, 320 10 L 320 150 L 0 150 Z" fill="url(#site-earn-fill)" />
        <path d="M0 134 C 110 134, 200 108, 258 62 C 288 38, 306 22, 320 10" fill="none" stroke="#3ecf8e" strokeWidth="3" strokeLinecap="round" />
        <circle cx="320" cy="10" r="5" fill="#3ecf8e" />
      </svg>
      <div className="site-earn-labels">
        <span>Today</span>
        <span>In one year</span>
      </div>
    </div>
  );
}

const handles: Array<[handle: string, initial: string, color: string]> = [
  ["@ade", "A", "#f07539"],
  ["@zara", "Z", "#8c5cf5"],
  ["@tobi", "T", "#3b82f6"],
];

export function HandleChips() {
  return (
    <div className="site-handles">
      {handles.map(([handle, initial, color]) => (
        <span key={handle} className="site-handle">
          <span className="site-handle-avatar" style={{ background: color }}>
            {initial}
          </span>
          {handle}
        </span>
      ))}
    </div>
  );
}

export function ChequeSlip() {
  return (
    <div className="site-cheque">
      <div className="site-cheque-head">
        <span>Cheque</span>
        <span className="site-cheque-status">Waiting</span>
      </div>
      <div className="site-cheque-amount">$25.00</div>
      <div className="site-cheque-to">to @zara</div>
      <div className="site-cheque-rule" />
      <div className="site-cheque-foot">
        <span>Cash it any time</span>
        <span className="site-cheque-void">Void</span>
      </div>
    </div>
  );
}

export function ConvertPair() {
  return (
    <div className="site-convert">
      <div className="site-convert-coin">
        <Image src="/brand/usdc.svg" alt="" width={48} height={48} className="site-convert-disc" />
        <span>USDC</span>
      </div>
      <ArrowRight size={20} className="site-convert-arrow" aria-hidden="true" />
      <div className="site-convert-coin">
        <span className="site-convert-disc site-convert-euro">€</span>
        <span>EURC</span>
      </div>
    </div>
  );
}

export function FeeTag() {
  return (
    <div className="site-fee">
      <span className="site-tag">
        <Tag size={15} strokeWidth={2} aria-hidden="true" />0 extra tokens
      </span>
      <span className="site-fee-note">fee paid in USDC</span>
    </div>
  );
}
