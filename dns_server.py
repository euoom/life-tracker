"""Minimal DNS proof-of-concept for the custom YouTube gateway."""

import os
from dnslib import A, DNSRecord, QTYPE, RR
from dnslib.server import BaseResolver, DNSServer, DNSLogger

LISTEN_HOST = os.getenv("DNS_LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.getenv("DNS_LISTEN_PORT", "53"))
REDIRECT_IP = os.getenv("REDIRECT_IP", "192.168.1.152")
UPSTREAM_DNS = os.getenv("UPSTREAM_DNS", "1.1.1.1")
BLOCKED_SUFFIXES = ("youtube.com.", "www.youtube.com.", "m.youtube.com.")


class GatewayResolver(BaseResolver):
    def resolve(self, request, handler):
        reply = request.reply()
        qname = str(request.q.qname).lower()
        is_youtube = any(qname == suffix or qname.endswith("." + suffix) for suffix in BLOCKED_SUFFIXES)
        qtype = QTYPE[request.q.qtype]
        if is_youtube and qtype in ("A", "ANY"):
            reply.add_answer(RR(request.q.qname, QTYPE.A, rdata=A(REDIRECT_IP), ttl=30))
            print(f"[redirect A] {qname} -> {REDIRECT_IP}", flush=True)
        elif is_youtube and qtype in ("AAAA", "HTTPS"):
            print(f"[suppress {qtype}] {qname}", flush=True)
        else:
            try:
                reply = DNSRecord.parse(request.send(UPSTREAM_DNS, 53, timeout=2))
                print(f"[forward] {qname} -> {UPSTREAM_DNS}", flush=True)
            except Exception as exc:
                print(f"[error] {qname}: {exc}", flush=True)
        return reply


if __name__ == "__main__":
    print(f"DNS listening on {LISTEN_HOST}:{LISTEN_PORT}; redirect={REDIRECT_IP}", flush=True)
    DNSServer(GatewayResolver(), port=LISTEN_PORT, address=LISTEN_HOST, logger=DNSLogger(prefix="", log="request,error")).start()
