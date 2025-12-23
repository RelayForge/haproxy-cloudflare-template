# HAProxy Configuration Guide

This guide covers HAProxy configuration for common use cases.

## Configuration File Structure

```haproxy
#---------------------------------------------------------------------
# Global settings - Process-level configuration
#---------------------------------------------------------------------
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    user haproxy
    group haproxy
    daemon

#---------------------------------------------------------------------
# Defaults - Applied to all frontends/backends unless overridden
#---------------------------------------------------------------------
defaults
    log     global
    mode    http
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

#---------------------------------------------------------------------
# Frontend - Entry points for traffic
#---------------------------------------------------------------------
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/
    # ACLs and routing rules

#---------------------------------------------------------------------
# Backend - Groups of servers handling requests
#---------------------------------------------------------------------
backend my_backend
    balance roundrobin
    server srv1 10.0.0.1:8080 check
```

## SSL/TLS Configuration

### Certificate Format

HAProxy expects PEM bundles containing (in order):
1. Private key
2. Server certificate
3. Intermediate certificates

```bash
# Combine certificate files
cat private.key certificate.crt intermediate.crt > domain.pem

# Copy to HAProxy certs directory
sudo cp domain.pem /etc/haproxy/certs/
sudo chmod 600 /etc/haproxy/certs/domain.pem
```

### SSL Frontend

```haproxy
frontend https_front
    # Load all certificates from directory
    bind *:443 ssl crt /etc/haproxy/certs/

    # Or specify individual certificate
    # bind *:443 ssl crt /etc/haproxy/certs/example.com.pem

    # Force HTTPS
    http-request redirect scheme https unless { ssl_fc }
```

### HTTP to HTTPS Redirect

```haproxy
frontend http_front
    bind *:80
    http-request redirect scheme https code 301
```

## Load Balancing

### Algorithms

```haproxy
backend my_backend
    # Round robin (default) - equal distribution
    balance roundrobin

    # Least connections - send to server with fewest connections
    # balance leastconn

    # Source IP hash - same client always goes to same server
    # balance source

    # URI hash - same URL always goes to same server
    # balance uri
```

### Server Options

```haproxy
backend my_backend
    balance roundrobin

    server srv1 10.0.0.1:8080 check inter 5s fall 3 rise 2 weight 100
    server srv2 10.0.0.2:8080 check inter 5s fall 3 rise 2 weight 100
    server srv3 10.0.0.3:8080 check inter 5s fall 3 rise 2 backup

    # Options explained:
    # check         - Enable health checks
    # inter 5s      - Check every 5 seconds
    # fall 3        - Mark down after 3 consecutive failures
    # rise 2        - Mark up after 2 consecutive successes
    # weight 100    - Relative weight for load balancing
    # backup        - Only use if all primary servers are down
```

## Health Checks

### HTTP Health Check

```haproxy
backend api_backend
    option httpchk GET /health
    http-check expect status 200

    server api1 10.0.0.1:3000 check
    server api2 10.0.0.2:3000 check
```

### TCP Health Check

```haproxy
backend db_backend
    mode tcp
    option tcp-check

    server db1 10.0.0.1:5432 check
    server db2 10.0.0.2:5432 check
```

### Custom Health Check

```haproxy
backend custom_backend
    option httpchk
    http-check send meth GET uri /api/health hdr Host api.example.com
    http-check expect string "healthy"

    server app1 10.0.0.1:8080 check
```

## Host-Based Routing

```haproxy
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/

    # Define host ACLs
    acl is_www hdr(host) -i www.example.com example.com
    acl is_api hdr(host) -i api.example.com
    acl is_admin hdr(host) -i admin.example.com

    # Route to backends
    use_backend www_backend if is_www
    use_backend api_backend if is_api
    use_backend admin_backend if is_admin

    # Default backend
    default_backend www_backend
```

## Path-Based Routing

```haproxy
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/

    # Define path ACLs
    acl is_api path_beg /api/
    acl is_static path_beg /static/ /assets/ /images/
    acl is_websocket path_beg /ws/

    # Route to backends
    use_backend api_backend if is_api
    use_backend static_backend if is_static
    use_backend websocket_backend if is_websocket

    default_backend www_backend
```

## Session Persistence (Sticky Sessions)

### Cookie-Based

```haproxy
backend admin_backend
    balance roundrobin
    cookie SERVERID insert indirect nocache

    server admin1 10.0.0.1:4173 check cookie admin1
    server admin2 10.0.0.2:4173 check cookie admin2
    server admin3 10.0.0.3:4173 check cookie admin3
```

### Source IP-Based

```haproxy
backend session_backend
    balance source
    hash-type consistent

    server app1 10.0.0.1:8080 check
    server app2 10.0.0.2:8080 check
```

## Rate Limiting

```haproxy
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/

    # Track requests per IP
    stick-table type ip size 100k expire 30s store http_req_rate(10s)
    http-request track-sc0 src

    # Deny if more than 100 requests in 10 seconds
    http-request deny deny_status 429 if { sc_http_req_rate(0) gt 100 }
```

## Headers

### Add/Modify Headers

```haproxy
frontend https_front
    # Add X-Forwarded headers
    option forwardfor
    http-request set-header X-Forwarded-Proto https if { ssl_fc }
    http-request set-header X-Forwarded-Port %[dst_port]

backend my_backend
    # Add Host header if missing
    http-request set-header Host www.example.com unless { req.hdr(Host) -m found }
```

### Security Headers

```haproxy
frontend https_front
    http-response set-header X-Frame-Options SAMEORIGIN
    http-response set-header X-Content-Type-Options nosniff
    http-response set-header X-XSS-Protection "1; mode=block"
    http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    http-response del-header Server
```

## WebSocket Support

```haproxy
frontend https_front
    acl is_websocket hdr(Upgrade) -i websocket

    use_backend websocket_backend if is_websocket

backend websocket_backend
    balance source

    # Longer timeouts for WebSocket
    timeout tunnel 1h
    timeout client-fin 30s
    timeout server-fin 30s

    server ws1 10.0.0.1:8080 check
    server ws2 10.0.0.2:8080 check
```

## Stats Dashboard

```haproxy
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if LOCALHOST

    # Authentication
    stats auth admin:your-secure-password

    # Restrict to specific IPs
    acl allowed_ips src 10.0.0.0/8 192.168.0.0/16
    http-request deny unless allowed_ips
```

## Logging

### Syslog Configuration

```haproxy
global
    log /dev/log local0
    log /dev/log local1 notice

defaults
    log global
    option httplog
    option dontlognull
```

### Custom Log Format

```haproxy
defaults
    log-format "%ci:%cp [%tr] %ft %b/%s %TR/%Tw/%Tc/%Tr/%Ta %ST %B %CC %CS %tsc %ac/%fc/%bc/%sc/%rc %sq/%bq %hr %hs %{+Q}r"
```

## Maintenance Mode

```haproxy
backend maintenance_backend
    mode http
    http-request return status 503 content-type "text/html" lf-file /etc/haproxy/errors/503.http

# In frontend, use ACL to enable maintenance mode
frontend https_front
    acl maintenance_mode nbsrv(www_backend) eq 0

    use_backend maintenance_backend if maintenance_mode
```

## Validation

Always validate configuration before applying:

```bash
# Syntax check
haproxy -c -f /etc/haproxy/haproxy.cfg

# Verbose output
haproxy -c -f /etc/haproxy/haproxy.cfg -V
```

## Common Issues

### "No server available"

- Check backend servers are running
- Verify health check endpoints return expected response
- Check network connectivity from HAProxy to backends

### "Connection refused"

- Verify bind address and port are correct
- Check firewall rules allow traffic
- Ensure HAProxy service is running

### "SSL handshake failure"

- Verify certificate bundle order is correct
- Check certificate is not expired
- Ensure private key matches certificate

### "503 Service Unavailable"

- All backend servers are marked down
- Health checks are failing
- Check backend server logs
