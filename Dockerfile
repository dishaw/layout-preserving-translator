FROM nginx:alpine

# 每30分钟清理 /uploads/ 中超过2小时的临时文件
RUN echo '*/30 * * * * find /usr/share/nginx/html/uploads -mindepth 1 -type f -mmin +120 -delete; find /usr/share/nginx/html/uploads -mindepth 1 -type d -empty -delete' \
    > /etc/crontabs/root

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY . /usr/share/nginx/html
RUN mkdir -p /usr/share/nginx/html/uploads \
    && chmod 777 /usr/share/nginx/html/uploads

EXPOSE 80
CMD ["/docker-entrypoint.sh"]
