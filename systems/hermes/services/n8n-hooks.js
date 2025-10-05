const { dirname, resolve } = require('path');
const Layer = require('router/lib/layer');
const { issueCookie } = require(resolve(dirname(require.resolve('n8n')), 'auth/jwt'));

const ignoreAuthRegexp = /^\/(?:assets|healthz|webhook|rest\/oauth2-credential)/;

module.exports = {
  n8n: {
    ready: [
      async function ({ app }, config) {
        const { stack } = app.router;
        const index = stack.findIndex((l) => l.name === 'cookieParser');
        stack.splice(index + 1, 0, new Layer('/', {
          strict: false,
          end: false
        }, async (req, res, next) => {
          if (ignoreAuthRegexp.test(req.url)) return next();

          if (!config.get('userManagement.isInstanceOwnerSetUp', false)) return next();

          if (req.cookies?.['n8n-auth']) return next();

          const remoteUser = req.headers['remote-user'];
          if (!remoteUser) return next();

          try {
            const user = await this.dbCollections.User.findOneBy({ email: remoteUser });

            if (!user) {
              res.statusCode = 401;
              res.end(`User ${remoteUser} not found. Please have an admin invite the user first.`);
              return;
            }

            if (!user.role) {
              user.role = {};
            }

            const token = issueCookie(res, user);

            req.cookies = req.cookies || {};
            req.cookies['n8n-auth'] = token;

            next();
          } catch (error) {
            console.error('Authelia auth bypass error:', error);
            res.statusCode = 500;
            res.end('Internal server error during authentication');
          }
        }));
      }
    ]
  }
};