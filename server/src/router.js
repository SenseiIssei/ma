// A tiny path matcher: "/circles/:id/leave" becomes a regex with named
// groups. Enough for a dozen routes, and nothing to install.

export function compileRoutes(routes) {
  return routes.map((route) => {
    const names = [];
    const pattern = route.path
      .split('/')
      .map((part) => {
        if (part.startsWith(':')) {
          names.push(part.slice(1));
          return '([^/]+)';
        }
        return part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      })
      .join('/');
    return { ...route, regex: new RegExp(`^${pattern}$`), names };
  });
}

/**
 * Finds the route for method and path. Returns { route, params } on a hit,
 * { allowed: [...] } when the path exists under other methods, or null.
 */
export function matchRoute(compiled, method, path) {
  const allowed = [];
  for (const route of compiled) {
    const m = route.regex.exec(path);
    if (!m) continue;
    if (route.method !== method) {
      allowed.push(route.method);
      continue;
    }
    const params = {};
    route.names.forEach((name, i) => {
      try {
        params[name] = decodeURIComponent(m[i + 1]);
      } catch {
        params[name] = '';
      }
    });
    return { route, params };
  }
  return allowed.length ? { allowed } : null;
}
