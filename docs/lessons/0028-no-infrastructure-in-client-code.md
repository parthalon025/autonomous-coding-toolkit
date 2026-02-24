---
id: 28
title: "Never embed infrastructure details in client-side code"
severity: blocker
languages: [javascript, typescript]
scope: [universal]
category: silent-failures
pattern:
  type: syntactic
  regex: "['\"]https?://\\d+\\.\\d+\\.\\d+\\.\\d+"
  description: "Hardcoded IP addresses or localhost URLs in client-side code"
fix: "Use relative URLs, environment variables, or a config endpoint"
example:
  bad: |
    // hardcoded IP in client code
    const API_URL = 'http://192.168.1.100:8080';

    fetch(`${API_URL}/users`)
      .then(r => r.json())
      .then(data => console.log(data));
  good: |
    // Use relative URL or environment variable
    const API_URL = process.env.REACT_APP_API_URL || '/api';

    fetch(`${API_URL}/users`)
      .then(r => r.json())
      .then(data => console.log(data));
---

## Observation

Client-side code containing hardcoded IP addresses, `localhost:port` URLs, or internal hostnames breaks when deployed to different environments. These details change between development, staging, and production, but hardcoding them means shipping different code for each environment.

## Insight

Client-side code is delivered to users' browsers and cannot be changed post-deployment. Infrastructure details (which IP, which port) are deployment decisions, not code decisions. Embedding them couples code to infrastructure and breaks portability.

## Lesson

Never hardcode infrastructure details in client code:

1. **Relative URLs**: Use `fetch('/api/users')` instead of `fetch('http://192.168.1.100:8080/api/users')`. The browser sends requests to the same origin.
2. **Environment variables**: Use `process.env.REACT_APP_API_URL` (React) or similar, set at build time per environment.
3. **Config endpoint**: On app startup, fetch config from a well-known endpoint, then use returned URLs.
4. **DNS names**: Use domain names (`api.example.com`), not IP addresses. IPs change; domains don't.

Verification: Deploy the same compiled artifact to three environments (dev, staging, prod) and verify it connects to the correct backend in each. If you need to rebuild for each environment, you've embedded infrastructure.

This applies equally to API keys — never hardcode them. Use environment variables or secure token exchange.
