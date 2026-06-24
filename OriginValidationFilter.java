package ir.bankmellat.token.config;

import jakarta.servlet.*;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;

/**
 * Hard-blocks any request whose Origin header does not exactly match
 * the configured banking portal URL.
 *
 * This prevents other websites from silently calling the local agent
 * even if the user has the agent running.
 */
public class OriginValidationFilter implements Filter {

    private static final Logger log = LoggerFactory.getLogger(OriginValidationFilter.class);

    private final String allowedOrigin;

    public OriginValidationFilter(String allowedOrigin) {
        this.allowedOrigin = allowedOrigin;
    }

    @Override
    public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain)
            throws IOException, ServletException {

        HttpServletRequest  request  = (HttpServletRequest)  req;
        HttpServletResponse response = (HttpServletResponse) res;

        String method = request.getMethod();
        String origin = request.getHeader("Origin");
        String referer = request.getHeader("Referer");

        // Allow OPTIONS (CORS preflight) to pass through to CORS handler
        if ("OPTIONS".equalsIgnoreCase(method)) {
            chain.doFilter(req, res);
            return;
        }

        // Actuator health check — no origin required
        if (request.getRequestURI().startsWith("/actuator")) {
            chain.doFilter(req, res);
            return;
        }

        // Validate Origin header
        boolean originOk  = allowedOrigin.equals(origin);
        boolean refererOk = referer != null && referer.startsWith(allowedOrigin);

        if (!originOk && !refererOk) {
            log.warn("Blocked request from unauthorized origin='{}' referer='{}' uri='{}'",
                origin, referer, request.getRequestURI());
            response.setStatus(HttpServletResponse.SC_FORBIDDEN);
            response.setContentType("application/json");
            response.getWriter().write(
                "{\"error\":\"Unauthorized origin\",\"code\":\"ORIGIN_BLOCKED\"}"
            );
            return;
        }

        chain.doFilter(req, res);
    }
}
