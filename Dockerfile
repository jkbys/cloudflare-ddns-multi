FROM alpine:3.12
RUN apk add --no-cache curl jq
COPY cloudflare-multi-ddns.sh /
CMD ["/cloudflare-multi-ddns.sh"]
