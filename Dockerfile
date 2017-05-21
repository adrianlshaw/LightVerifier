FROM debian:jessie
WORKDIR /testsite/
RUN apt-get -qq update
RUN apt-get install -y git make gcc netcat-traditional tpm-tools libtspi-dev git autoconf redis-server redis-tools
RUN cd tpm-quote-tools && autoreconf -i
COPY . 
RUN ./configure
RUN make install
RUN cd ..
ENTRYPOINT ["bash", "tests/test-script.sh"]
