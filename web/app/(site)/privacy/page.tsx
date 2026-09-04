import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Privacy policy",
  description: "What Recourse collects, which keys never leave your device, and what lives permanently on the public Arc chain.",
};

export default function PrivacyPage() {
  return (
    <article className="site-wrap site-legal">
      <h1 className="site-h1">Privacy policy</h1>
      <p className="site-legal-updated">Last updated September 4, 2026</p>

      <p>
        Recourse is a money app for USDC on the Arc testnet. This policy covers the Recourse iOS app, the website at
        recourse-arc.vercel.app, and Olien, the web console for team treasuries. It is written to be read, not skimmed
        past: the product&apos;s whole premise is that you should not have to trust us, and that starts with being plain
        about data.
      </p>

      <h2>What we collect</h2>
      <p>
        <strong>Account details.</strong> The iOS app signs you in with Apple, Google, or a passkey. We store the
        email address and display name that sign-in gives us to run your session, to send the code that recovers your
        account on a new phone, and to identify you to people who pay you. There is no web account for the app:
        nothing on this site logs you into it.
      </p>
      <p>
        <strong>Your handle and account address.</strong> When you set up the app you choose an @handle. We store it
        together with the address of your smart account so that other people can pay you by name.
      </p>
      <p>
        <strong>Olien sign-in.</strong> Olien has no passwords either. You sign in by signing a message with your wallet,
        and we keep the wallet address and the session that signature opened.
      </p>
      <p>
        <strong>Requests and cheques in flight.</strong> A request you send and a cheque you write are held by our
        backend until the other person pays or cashes it, or you void it. That is what lets a cheque wait in someone
        else&apos;s app.
      </p>
      <p>
        <strong>Payment data, which is public by design.</strong> Payments, cashed cheques, conversions, Earn deposits,
        and the keys that make up your smart account are recorded on the public Arc blockchain. Anyone can read them,
        and they cannot be edited or deleted by anyone, including us. Account addresses are pseudonymous but permanent,
        and a handle that points at an address links the two for anyone who looks.
      </p>

      <h2>Your keys</h2>
      <p>
        <strong>The key on your phone.</strong> The iOS app generates one of your three signing keys inside the
        device&apos;s Secure Enclave. It cannot be exported, and we never see, transmit, or hold it.
      </p>
      <p>
        <strong>Your iCloud key.</strong> The second key is stored in your iCloud, so it follows you to a new iPhone. It
        never reaches us.
      </p>
      <p>
        <strong>The recovery key.</strong> The third key is sealed by our backend. On its own it cannot move money: the
        account is a 2-of-3 smart account, so every payment needs one of your keys as well. It is used only to bring the
        account back on a new phone, after a code sent to your email proves it is you, and only alongside your iCloud
        key.
      </p>
      <p>
        <strong>Face ID.</strong> Biometric checks run entirely through Apple&apos;s system frameworks on your device.
        No biometric data reaches us, ever.
      </p>

      <h2>What we do not do</h2>
      <p>
        No advertising, no analytics trackers, no selling or sharing of data with third parties for marketing, no
        profiling. The backend logs ordinary operational records (such as request errors) to keep the service running.
      </p>

      <h2>Retention and deletion</h2>
      <p>
        Your handle, display name, and anything held off-chain, such as open requests and uncashed cheques, are kept
        while your account is active. Email us to delete them. Data recorded on the Arc blockchain is immutable and
        cannot be deleted by design; that permanence is what makes the balance yours.
      </p>

      <h2>Testnet notice</h2>
      <p>
        Recourse currently runs on the Arc testnet. Balances are test tokens with no monetary value, and no real funds
        are handled.
      </p>

      <h2>Contact</h2>
      <p>
        Questions or deletion requests: <a href="mailto:gkenny896@gmail.com">gkenny896@gmail.com</a>.
      </p>
    </article>
  );
}
