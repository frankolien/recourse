import type { ReactNode } from "react";
import type { LucideIcon } from "lucide-react";
import {
  ArrowLeftRight,
  Check,
  Cloud,
  Delete,
  FileText,
  KeyRound,
  Receipt,
  ShieldCheck,
  Smartphone,
  Sprout,
} from "lucide-react";

function StatusBar() {
  return (
    <div className="site-phone-status">
      <span>9:41</span>
      <span className="site-phone-status-glyphs">
        <svg width="17" height="11" viewBox="0 0 17 11" fill="currentColor">
          <rect x="0" y="7" width="3" height="4" rx="0.8" />
          <rect x="4.5" y="5" width="3" height="6" rx="0.8" />
          <rect x="9" y="2.5" width="3" height="8.5" rx="0.8" />
          <rect x="13.5" y="0" width="3" height="11" rx="0.8" />
        </svg>
        <svg width="16" height="12" viewBox="0 0 16 12" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
          <path d="M1.5 4.2a9.5 9.5 0 0 1 13 0" />
          <path d="M4 7a5.8 5.8 0 0 1 8 0" />
          <path d="M6.6 9.7a2.2 2.2 0 0 1 2.8 0" />
        </svg>
        <svg width="25" height="12" viewBox="0 0 25 12" fill="none">
          <rect x="0.5" y="0.5" width="21" height="11" rx="3" stroke="currentColor" opacity="0.4" />
          <rect x="2" y="2" width="18" height="8" rx="1.8" fill="currentColor" />
          <path d="M23 4v4a2 2 0 0 0 0-4Z" fill="currentColor" opacity="0.4" />
        </svg>
      </span>
    </div>
  );
}

// The whole mockup reads as one image to assistive tech; the screen contents are decoration.
function Frame({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="site-phone" role="img" aria-label={label}>
      <div className="site-phone-screen" aria-hidden="true">
        <div className="site-phone-island" />
        <StatusBar />
        {children}
      </div>
    </div>
  );
}

// Bar heights as a percentage of the chart, grouped into flat runs so the chart
// reads as a staircase of deposits and spends rather than a smooth line.
const chartSteps: Array<[count: number, height: number]> = [
  [4, 30],
  [5, 36],
  [4, 28],
  [5, 40],
  [4, 46],
  [4, 34],
  [5, 56],
  [4, 62],
  [3, 50],
  [4, 76],
  [2, 86],
];
const chartBars = chartSteps.flatMap(([count, height]) => Array.from({ length: count }, () => height));
const ranges = ["1D", "1W", "1M", "6M", "1Y"];

const tiles: Array<{ name: string; sub: string; tint: string; Icon: LucideIcon }> = [
  { name: "Cheques", sub: "Write, cash or void", tint: "green", Icon: FileText },
  { name: "Request", sub: "Bill someone by name", tint: "orange", Icon: Receipt },
  { name: "Convert", sub: "USDC to EURC", tint: "blue", Icon: ArrowLeftRight },
  { name: "Earn", sub: "Yield on idle USDC", tint: "purple", Icon: Sprout },
];

export function PhoneHome() {
  return (
    <Frame label="The Recourse home screen: a balance of $1,240.50, $120.00 waiting to be cashed, a week of activity, and tiles for Cheques, Request, Convert and Earn">
      <div className="site-ph-header">
        <span className="site-ph-avatar">F</span>
        <div>
          <div className="site-ph-name">Frank</div>
          <div className="site-ph-net">USDC on Arc Testnet</div>
        </div>
      </div>
      <div className="site-ph-label">Balance</div>
      <div className="site-ph-balance">
        $1,240<small>.50</small>
      </div>
      <div className="site-ph-waiting">$120.00 waiting for you to cash</div>
      <div className="site-ph-chart">
        {chartBars.map((height, i) => (
          <span key={i} style={{ height: `${height}%` }} />
        ))}
      </div>
      <div className="site-ph-ranges">
        {ranges.map((range) => (
          <span key={range} className={range === "1W" ? "site-ph-range is-active" : "site-ph-range"}>
            {range}
          </span>
        ))}
      </div>
      <div className="site-ph-actions">
        <span className="site-ph-pill">Add money</span>
        <span className="site-ph-pill is-green">Send</span>
      </div>
      <div className="site-ph-grid">
        {tiles.map(({ name, sub, tint, Icon }) => (
          <div key={name} className="site-ph-tile">
            <span className={`site-ph-tile-icon site-ph-tint-${tint}`}>
              <Icon size={15} strokeWidth={2} />
            </span>
            <div className="site-ph-tile-name">{name}</div>
            <div className="site-ph-tile-sub">{sub}</div>
          </div>
        ))}
      </div>
    </Frame>
  );
}

const keypad = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "delete"];

export function PhoneSend() {
  return (
    <Frame label="The Recourse send screen: $40.00 to @ade with the note for lunch, a number pad, and a green Send button">
      <div className="site-ph-sendto">
        <span>Send to</span>
        <span className="site-ph-chip">
          <span className="site-ph-chip-avatar">A</span>@ade
        </span>
      </div>
      <div className="site-ph-amount">$40.00</div>
      <div className="site-ph-note">for lunch</div>
      <div className="site-ph-keypad">
        {keypad.map((key) => (
          <span key={key} className="site-ph-key">
            {key === "delete" ? <Delete size={22} strokeWidth={1.8} /> : key}
          </span>
        ))}
      </div>
      <div className="site-ph-send">Send</div>
    </Frame>
  );
}

const keyRows: Array<{ Icon: LucideIcon; title: string; sub: string }> = [
  { Icon: Smartphone, title: "This iPhone", sub: "Secure Enclave, unlocks with Face ID" },
  { Icon: Cloud, title: "iCloud key", sub: "Restores on a new phone" },
  { Icon: KeyRound, title: "Recovery key", sub: "Sealed, cannot spend alone" },
];

export function PhoneKeys() {
  return (
    <Frame label="The Recourse keys screen: This iPhone, iCloud key and Recovery key, each checked, and the line 2 of 3 sign every payment">
      <div className="site-ph-title">Your keys</div>
      <ul className="site-ph-keys">
        {keyRows.map(({ Icon, title, sub }) => (
          <li key={title} className="site-ph-key-row">
            <span className="site-ph-key-icon">
              <Icon size={18} strokeWidth={1.8} />
            </span>
            <span>
              <span className="site-ph-key-title">{title}</span>
              <span className="site-ph-key-sub">{sub}</span>
            </span>
            <span className="site-ph-key-check">
              <Check size={12} strokeWidth={3} />
            </span>
          </li>
        ))}
      </ul>
      <div className="site-ph-footer">
        <ShieldCheck size={14} strokeWidth={2} />
        <span>2 of 3 sign every payment</span>
      </div>
    </Frame>
  );
}
