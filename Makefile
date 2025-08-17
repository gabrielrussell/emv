CC = gcc
CFLAGS = -Wall -Wextra -std=c99 -O2
TARGET = emv
SOURCE = emv.c

$(TARGET): $(SOURCE)
	$(CC) $(CFLAGS) -o $(TARGET) $(SOURCE)

clean:
	rm -f $(TARGET)

install: $(TARGET)
	cp $(TARGET) /usr/local/bin/
	mkdir -p /usr/local/share/man/man1
	cp emv.1 /usr/local/share/man/man1/
	gzip -f /usr/local/share/man/man1/emv.1

test: $(TARGET)
	./test.sh

test-valgrind: $(TARGET)
	VALGRIND=1 ./test.sh

.PHONY: clean install test test-valgrind
