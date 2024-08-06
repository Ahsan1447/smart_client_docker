ARG DISTRO="debian"
ARG DISTRO_VARIANT="bullseye"

FROM docker.io/tiredofit/nginx:${DISTRO}-${DISTRO_VARIANT}
LABEL maintainer="Dave Conroy (github.com/tiredofit)"

# Arguments
ARG DISCOURSE_VERSION
ARG RUBY_VERSION

# Environment Variables
ENV DISCOURSE_VERSION=${DISCOURSE_VERSION:-"v3.2"} \
    RUBY_VERSION=${RUBY_VERSION:-"3.2.1"} \
    RUBY_ALLOCATOR=/usr/lib/libjemalloc.so.2 \
    RAILS_ENV=development \
    RUBY_GC_MALLOC_LIMIT=90000000 \
    RUBY_GLOBAL_METHOD_CACHE_SIZE=131072 \
    ENABLE_NGINX=FALSE \
    NGINX_MODE=PROXY \
    NGINX_PROXY_URL=http://127.0.0.1:3000 \
    NGINX_ENABLE_CREATE_SAMPLE_HTML=FALSE \
    IMAGE_NAME="tiredofit/discourse" \
    IMAGE_REPO_URL="https://github.com/Ahsan1447/discourse/" \
    REDIS_URL=redis://discourse-redis:6379

# Install Dependencies
RUN apt-get update && \
    apt-get install -y \
        libyaml-dev \
        build-essential \
        libbz2-dev \
        libfreetype6-dev \
        libjemalloc-dev \
        libjpeg-dev \
        libssl-dev \
        libpq-dev \
        libtiff-dev \
        libxslt-dev \
        libxml2-dev \
        pkg-config \
        zlib1g-dev \
        curl \
        gnupg \
        lsb-release \
        git \
        make \
        ca-certificates && \
        set -x && \
    addgroup --gid 9009 --system discourse && \
    adduser --uid 9009 --gid 9009 --home /dev/null --gecos "Discourse" --shell /sbin/nologin --disabled-password discourse && \
    # Install a specific version of Node.js
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    # Add Yarn repository and install Yarn
    curl -sSL https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
    echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list && \
    apt-get update && \
    apt-get install -y yarn && \
    # Add PostgreSQL repository and install PostgreSQL client
    curl -ssL https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/postgres.list && \
    apt-get update && \
    apt-get install -y postgresql-client-15 postgresql-contrib-15 && \
    # Install additional packages
    apt-get install -y \
        advancecomp \
        brotli \
        ghostscript \
        gifsicle \
        gsfonts \
        jhead \
        jpegoptim \
        libicu67 \
        libjemalloc2 \
        libjpeg-turbo-progs \
        libpq5 \
        libssl1.1 \
        libxml2 \
        optipng \
        pngquant \
        zlib1g && \
    # Install ImageMagick 7 from source
    apt-get install -y \
        wget \
        software-properties-common && \
    wget https://github.com/ImageMagick/ImageMagick/archive/refs/tags/7.1.0-61.tar.gz && \
    tar xvzf 7.1.0-61.tar.gz && \
    cd ImageMagick-7.1.0-61 && \
    ./configure && \
    make && \
    make install && \
    ldconfig /usr/local/lib && \
    cd .. && \
    rm -rf ImageMagick-7.1.0-61 7.1.0-61.tar.gz && \
    # Clean up
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Ruby
RUN mkdir -p /usr/src/ruby && \
    curl -sSL https://cache.ruby-lang.org/pub/ruby/$(echo ${RUBY_VERSION} | cut -c1-3)/ruby-${RUBY_VERSION}.tar.gz | tar xvfz - --strip 1 -C /usr/src/ruby && \
    cd /usr/src/ruby && \
    ./configure \
        --disable-install-rdoc \
        --enable-shared \
        --with-jemalloc && \
    make -j$(getconf _NPROCESSORS_ONLN) && \
    make install && \
    echo 'gem: --no-document' >> /usr/local/etc/gemrc && \
    gem update --system

# Install npm packages
RUN npm install -g npm@10.8.2 && \
        npm install --global \
        svgo \
        terser \
        uglify-js \
        pnpm

# Download and setup Discourse
RUN git clone "https://github.com/Ahsan1447/smart_client_discourse" /app && \
    BUNDLER_VERSION="$(grep "BUNDLED WITH" /app/Gemfile.lock -A 1 | grep -v "BUNDLED WITH" | tr -d "[:space:]")" && \
    gem install bundler:"${BUNDLER_VERSION}" && \
    cd /app && \
    bundle config build.nokogiri --use-system-libraries && \
    bundle config --local path ./vendor/bundle && \
    bundle config set --local deployment true && \
    # bundle config set --local without development test && \
    bundle install --jobs 4 && \
    yarn install && \
    yarn cache clean && \
    cd /app/app/assets/javascripts/discourse && \
    /app/node_modules/.bin/ember build -prod && \
    # bundle exec rake maxminddb:get && \
    find /app/vendor/bundle -name tmp -type d -exec rm -rf {} + && \
    sed -i "5i\ \ require 'uglifier'" /app/config/environments/development.rb && \
    sed -i "s|config.assets.js_compressor = :uglifier|config.assets.js_compressor = Uglifier.new(harmony: true)|g" /app/config/environments/development.rb

RUN git config --global --add safe.directory /app

# Install Plugins
RUN mkdir -p /assets/discourse/plugins && \
    mv /app/plugins/* /assets/discourse/plugins && \
    rm -rf /assets/discourse/plugins/discourse-nginx-performance-report && \
    git clone https://github.com/TheBunyip/discourse-allow-same-origin.git /assets/discourse/plugins/allow-same-origin && \
    git clone https://github.com/discourse/discourse-solved /assets/discourse/plugins/solved && \
    git clone https://github.com/discourse/discourse-assign /assets/discourse/plugins/assign && \
    # git clone https://github.com/cpradio/discourse-plugin-checklist /assets/discourse/plugins/checklist && \
    git clone https://github.com/angusmcleod/discourse-events /assets/discourse/plugins/events && \
    # git clone https://github.com/discourse/discourse-footnote /assets/discourse/plugins/footnote && \
    git clone https://github.com/MonDiscourse/discourse-formatting-toolbar /assets/discourse/plugins/formatting-toolbar && \
    git clone https://github.com/unfoldingWord/discourse-mermaid /assets/discourse/plugins/mermaid && \
    git clone https://github.com/discourse/discourse-post-voting /assets/discourse/plugins/post-voting && \
    git clone https://github.com/discourse/discourse-push-notifications /assets/discourse/plugins/push && \
    ## Spoiler Alert
    # git clone https://github.com/discourse/discourse-spoiler-alert /assets/discourse/plugins/spoiler-alert && \
    ## Adds the ability for voting on a topic in category
    git clone https://github.com/discourse/discourse-voting.git /assets/discourse/plugins/voting && \
    # Ensure the directory exists before chown
    mkdir -p /assets/discourse/plugins && \
    chown -R discourse:discourse /assets/discourse /app

# Cleanup
RUN apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/ /tmp/ /usr/src/*

COPY database.yml /app/config/database.yml
COPY development.rb /app/config/environments/development.rb
COPY production.rb /app/config/environments/production.rb
WORKDIR /app
EXPOSE 3000 4200
COPY install/ /
