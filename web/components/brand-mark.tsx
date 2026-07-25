import Image from "next/image";

// The iOS app icon (cream R on ledger green) doubles as the web brand mark so both
// surfaces read as one product. Sized by the .brand-mark class at each call site.
export function BrandMark() {
  return (
    <Image
      src="/brand/recourse-mark.png"
      alt=""
      aria-hidden="true"
      width={64}
      height={64}
      className="brand-mark"
    />
  );
}
