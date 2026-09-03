// Served at /.well-known/apple-app-site-association. A route handler rather than a
// public/ file, because Apple's CDN requires the application/json content type.
//
// Passkeys are bound to a domain, and iOS checks this alongside the app's
// webcredentials entitlement before it will run a single ceremony. Both halves have to
// agree, and this half only takes effect when the web app is redeployed.
export function GET() {
  return Response.json({
    webcredentials: {
      apps: ["YCKKUWB4WD.com.recourse.buyer"],
    },
    // No applinks. The /pay universal link belonged to the protected checkout, and the
    // app no longer handles that URL: claiming it now would open the app and strand
    // whoever tapped it on the home screen. The web page still answers in Safari.
    applinks: {
      apps: [],
      details: [],
    },
  });
}
