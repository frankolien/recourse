import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  outputFileTracingRoot: path.join(process.cwd(), ".."),
  transpilePackages: ["@recourse/engine"],
  webpack: (config, { webpack }) => {
    // @recourse/engine is a file: dependency, which npm installs as a symlink. Webpack
    // resolves a module's imports from the file's real path, so engine's own imports
    // (viem, since the x402 and session modules were re-exported) are looked for in
    // engine/node_modules and its ancestors, and web/node_modules is not one of them.
    // Locally that directory usually exists; on Vercel only web's install runs.
    // Name web's node_modules as a fallback root, after the default nearest-first
    // walk: appended, not prepended, because putting it first would also capture
    // packages nested under other packages (wagmi's porto wants its own zod, not
    // web's) and break them instead.
    config.resolve.modules = [
      ...(config.resolve.modules ?? ["node_modules"]),
      path.resolve(process.cwd(), "node_modules"),
    ];
    // wagmi's bundled connectors (Coinbase, MetaMask, WalletConnect) reference
    // optional packages we neither install nor use (we only use the injected
    // connector): @x402/* via @coinbase/cdp-sdk, React Native async storage via
    // @metamask/sdk, and pino-pretty via WalletConnect logging. Ignore them.
    config.plugins.push(
      new webpack.IgnorePlugin({
        resourceRegExp: /^(@x402\/|pino-pretty$|@react-native-async-storage\/async-storage$)/,
      }),
    );
    return config;
  },
};

export default nextConfig;
