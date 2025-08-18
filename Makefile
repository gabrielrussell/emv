CC = gcc
CFLAGS = -Wall -Wextra -Werror -std=c99 -ggdb -O2
TARGET = emv
SOURCE = $(TARGET).c

all: $(TARGET) README.md

$(TARGET): $(SOURCE)
	$(CC) $(CFLAGS) -o $(TARGET) $(SOURCE)

clean:
	rm -f $(TARGET)
	rm $(TARGET).1.gz

README.md: $(TARGET).1
	pandoc -f man -t markdown $(TARGET).1 -o README.md

$(TARGET).1.gz: $(TARGET).1
	gzip -c $(TARGET).1 > $(TARGET).1.gz

install: $(TARGET) $(TARGET).1.gz
	cp $(TARGET) /usr/local/bin/
	mkdir -p /usr/local/share/man/man1
	cp $(TARGET).1.gz /usr/local/share/man/man1/

test: $(TARGET)
	./test.sh

test-valgrind: $(TARGET)
	VALGRIND=1 ./test.sh

test-verbose: $(TARGET)
	VERBOSE=1 ./test.sh

test-valgrind-verbose: $(TARGET)
	VALGRIND=1 VERBOSE=1 ./test.sh

.PHONY: clean install test test-valgrind test-verbose test-valgrind-verbose
