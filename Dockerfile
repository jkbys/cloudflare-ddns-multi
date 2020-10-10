FROM alpine:3.12
RUN apk add --no-cache curl jq
COPY cloudflare-ddns-multi.sh /
RUN ["chmod", "+x", "cloudflare-ddns-multi.sh"]
CMD ["/cloudflare-ddns-multi.sh"]
