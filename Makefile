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

.PHONY: clean install
