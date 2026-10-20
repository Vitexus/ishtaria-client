/* Default game-server URL for the browser client (ishtaria-client-web).
 *
 * The packaged copy under /usr/share/ishtaria-client-web/html/ is empty so no
 * public world is baked into the .deb. Each host sets its own value in
 * /etc/ishtaria/client-web-config.js (see debian/ishtaria-client-web.README.Debian)
 * and the Apache/nginx site aliases that file over this one — same name as the
 * desktop environment variable ISHTARIA_SERVER_URL.
 *
 * Examples:
 *   window.ISHTARIA_SERVER_URL = "https://world.example";
 *   window.ISHTARIA_SERVER_URL = "/";          // same origin (reverse proxy)
 *   window.ISHTARIA_SERVER_URL = "/server";    // same origin, /server → game API
 */
window.ISHTARIA_SERVER_URL = window.ISHTARIA_SERVER_URL || "";
