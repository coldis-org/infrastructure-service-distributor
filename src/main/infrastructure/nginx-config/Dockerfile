# From Nginx image.
FROM coldis/infrastructure-service-distributor-nginx:1.8.5

# Copies config.
COPY config/nginx /etc/nginx

# Configures scheduled jobs (cert and intranet updates).
COPY cron /etc/cron.d
RUN chmod -R 0644 /etc/cron.d/
	
# Copies the scripts.
RUN mkdir -p /opt/nginx-script
COPY script /opt/nginx-script
RUN chmod -R 755 /opt/nginx-script && \
	ln -s /opt/nginx-script/*.sh /usr/bin && \
	for FILE in /usr/bin/nginx*.sh; \
	do \
		mv -- "${FILE}" "${FILE%.sh}"; \
	done

# Variables.
ENV METRICSLOG=/dev/null

# Entrypoint.
ENTRYPOINT ["nginx_config_entrypoint"]
CMD ["nginx", "-g", "daemon off;"]
