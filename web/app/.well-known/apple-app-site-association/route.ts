// Served at /.well-known/apple-app-site-association so iOS registers /pay links as
// universal links into the Recourse app. A route handler (not a public/ file)
// guarantees the application/json content type Apple's CDN requires.
export function GET() {
  return Response.json({
    applinks: {
      apps: [],
      details: [
        {
          appIDs: ["YCKKUWB4WD.com.recourse.buyer"],
          components: [{ "/": "/pay*" }],
        },
      ],
    },
    // Passkeys are bound to a domain, and iOS checks this alongside the app's
    // webcredentials entitlement before it will run a single ceremony.
    webcredentials: {
      apps: ["YCKKUWB4WD.com.recourse.buyer"],
    },
  });
}
