# From Nginx image.
FROM coldis/infrastructure-service-distributor-nginx:1.1.0

# Copies config.
COPY config/nginx /etc/nginx

# Configures scheduled jobs (cert and intranet updates).
COPY cron /etc/cron.d
RUN chmod -R 0644 /etc/cron.d/ && \
	crontab /etc/cron.d/nginx_config_jobs
	
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

