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

test: $(TARGET)
	./test.sh

test-valgrind: $(TARGET)
	VALGRIND=1 ./test.sh

.PHONY: clean install test test-valgrind
