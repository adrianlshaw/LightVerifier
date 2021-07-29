FROM debian:jessie
WORKDIR /testsite/
RUN apt-get -qq update
RUN apt-get install -y -qq tpm2-tools git make gcc netcat-traditional vim-common tpm-tools \
	    libtspi-dev git autoconf redis-server redis-tools
COPY . /testsite/ 
RUN git submodule init && git submodule update
RUN cd tpm-quote-tools && autoreconf -i
RUN cd tpm-quote-tools && ./configure
RUN cd tpm-quote-tools && make install
ENTRYPOINT ["bash", "-c", "tests/test-script.sh && tests/2.0/test-script.sh"]
