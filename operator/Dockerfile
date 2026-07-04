ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.2
ARG DEBIAN_VERSION=trixie-20260623-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/
RUN mix deps.compile

COPY lib lib
RUN mix compile

COPY config/runtime.exs config/
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app
ENV MIX_ENV=prod

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/sqlites_operator ./

USER nobody

CMD ["/app/bin/sqlites_operator", "start"]
