# Copyright (c) 2022 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

SHELL=/bin/bash
.ONESHELL:
.SHELLFLAGS = -e -o pipefail -c
.PHONY: clean

INPUT = 32

CC=clang++
CCFLAGS=-mllvm --x86-asm-syntax=intel -O3 -fsanitize=leak
RUSTC=rustc
RUSTFLAGS=-O

DIRS=asm bin reports
CPPS = $(wildcard cpp/*.cpp)
RUSTS = $(wildcard rs/*.rs)
ASMS = $(subst rs/,asm/,$(subst cpp/,asm/,${CPPS:.cpp=.asm} ${RUSTS:.rs=.asm}))
BINS = $(subst asm/,bin/,${ASMS:.asm=.bin})
REPORTS = $(subst bin/,reports/,${BINS:.bin=.txt})

summary.txt: env $(DIRS) $(ASMS) $(BINS) $(REPORTS) $(CYCLES) Makefile
	[ $$({ for r in $(REPORTS:.txt=.stdout); do cat $${r}; done ; } | uniq | wc -l) == 1 ]
	{
		date
		$(CC) --version | head -1
		echo "INPUT=$(INPUT)"
		echo
		for r in $(REPORTS); do cat $${r}; done
	} > summary.txt
	cat "$@"

summary.csv: $(DIRS) $(REPORTS)
	{ for r in $(REPORTS:.txt=.csv); do cat $${r}; done } > summary.csv
	cat summary.csv

env:
	$(CC) --version
	$(RUSTC) --version
	$(MAKE) -version

sa: Makefile
	targets="include/*.h cpp/*.cpp"
	diff -u <(cat $${targets}) <(clang-format --style=file $${targets})
	cppcheck --inline-suppr --enable=all --std=c++11 --error-exitcode=1 $${targets}
	cpplint --extensions=cpp --filter=-whitespace/indent $${targets}
	clang-tidy -header-filter=none \
		'-warnings-as-errors=*' \
		'-checks=*,-readability-magic-numbers,-altera-id-dependent-backward-branch,-cert-err34-c,-cppcoreguidelines-avoid-non-const-global-variables,-readability-function-cognitive-complexity,-misc-no-recursion,-llvm-header-guard,-cppcoreguidelines-init-variables,-altera-unroll-loops,-clang-analyzer-valist.Uninitialized,-llvmlibc-callee-namespace,-cppcoreguidelines-no-malloc,-hicpp-no-malloc,-llvmlibc-implementation-in-namespace,-bugprone-easily-swappable-parameters,-llvmlibc-restrict-system-libc-headers,-llvm-include-order,-modernize-use-trailing-return-type,-cppcoreguidelines-special-member-functions,-hicpp-special-member-functions,-cppcoreguidelines-owning-memory,-cppcoreguidelines-pro-type-vararg,-hicpp-vararg' \
		$${targets}

asm/%.asm: cpp/%.cpp include/*.h
	$(CC) $(CCFLAGS) -S -o "$@" "$<"

asm/%.asm: rs/%.rs
	$(RUSTC) $(RUSTFLAGS) --emit=asm -o "$@" "$<"

bin/%.bin: cpp/%.cpp include/*.h
	$(CC) $(CCFLAGS) -o "$@" "$<"

bin/%.bin: rs/%.rs
	$(RUSTC) $(RUSTFLAGS) -o "$@" "$<"

reports/%.txt: bin/%.bin $(ASMS) Makefile $(DIRS)
	cycles=1
	while true; do
		time=$$({ time -p "$<" $(INPUT) $${cycles} | head -1 > "${@:.txt=.stdout}" ; } 2>&1 | head -1 | cut -f2 -d' ')
		echo $${time} > "${@:.txt=.time}"
		echo "cycles=$${cycles}; time=$${time} -> too fast, we will try again..."
		if [ "$(FAST)" != "" ]; then break; fi
		if [ "$$(echo $${time} | cut -f1 -d.)" -gt "0" -a "$${cycles}" -gt "7" ]; then break; fi
		cycles=$$(expr $${cycles} \* 2)
		if [ "$${cycles}" -lt "7" ]; then cycles=8; fi
	done
	instructions=$$(grep -e $$'^\(\t\| \)\+[a-z]\+' "$(subst bin/,asm/,${<:.bin=.asm})" | wc -l | xargs)
	per=$$(echo "scale = 16 ; $${time} / $${cycles}" | bc)
	{
	  	echo "$<:"
	  	echo "Instructions: $${instructions}"
		echo "Cycles: $${cycles}"
		echo "Time: $${time}"
		echo "Per cycle: $${per}"
		echo ""
	} > "$@"
	echo "${subst bin/,,$<},$${instructions},$${cycles},$${time},$${per}" > "${@:.txt=.csv}"

clean:
	rm -rf $(DIRS)
	rm -f summary.txt summary.csv

$(DIRS):
	mkdir "$@"
