import { NextResponse, type NextRequest } from "next/server";

const adminHosts = new Set([
  "admin.readtheworld.today",
  "admin.localhost",
]);

function hostnameFromRequest(request: NextRequest) {
  const forwardedHost =
    request.headers.get("x-forwarded-host") ??
    request.headers.get("x-fh-requested-host") ??
    request.headers.get("host") ??
    "";
  return forwardedHost.split(",")[0].split(":")[0].toLowerCase();
}

export function proxy(request: NextRequest) {
  const hostname = hostnameFromRequest(request);
  if (!adminHosts.has(hostname)) return NextResponse.next();

  const { pathname } = request.nextUrl;
  if (pathname === "/admin" || pathname.startsWith("/admin/")) {
    return NextResponse.next();
  }

  const url = request.nextUrl.clone();
  url.pathname = "/admin";
  return NextResponse.rewrite(url);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:png|jpg|jpeg|gif|webp|svg|ico|css|js|map)$).*)",
  ],
};
