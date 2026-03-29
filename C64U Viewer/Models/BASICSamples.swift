// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct BASICSample {
    let name: String
    let code: String
}

enum BASICSamples {

    static let all: [BASICSample] = [
        BASICSample(name: "Hello World", code: helloWorld),
        BASICSample(name: "Color Bars", code: colorBars),
        BASICSample(name: "Bouncing Ball", code: bouncingBall),
        BASICSample(name: "Number Guessing Game", code: numberGuess),
        BASICSample(name: "Maze Generator", code: mazeGenerator),
        BASICSample(name: "Starfield", code: starfield),
        BASICSample(name: "SID Sound Demo", code: sidSound),
        BASICSample(name: "Fibonacci Sequence", code: fibonacci),
    ]

    static let helloWorld = """
    10 print "{clr}"
    20 print "{down}{down}{down}"
    30 print "  {rvs on} hello from c64 ultimate toolbox! {rvs off}"
    40 print "{down}"
    50 for i=1 to 16
    60 print "{rvs on}                                        {rvs off}"
    70 next i
    80 goto 80
    """

    static let colorBars = """
    10 print "{clr}"
    20 c$="{blk}{wht}{red}{cyn}{pur}{grn}{blu}{yel}"
    30 c$=c$+"{org}{brn}{lred}{dgry}{mgry}{lgrn}{lblu}{lgry}"
    40 for y=0 to 24
    50 for x=0 to 15
    60 poke 1024+y*40+x*2,160
    70 poke 1024+y*40+x*2+1,160
    80 poke 55296+y*40+x*2,x
    90 poke 55296+y*40+x*2+1,x
    100 next x
    110 next y
    120 goto 120
    """

    static let bouncingBall = """
    10 print "{clr}"
    20 x=1:y=1:dx=1:dy=1
    30 poke 1024+y*40+x,81
    40 poke 55296+y*40+x,1
    50 for t=1 to 20:next t
    60 poke 1024+y*40+x,32
    70 x=x+dx:y=y+dy
    80 if x<1 or x>38 then dx=-dx
    90 if y<1 or y>23 then dy=-dy
    100 goto 30
    """

    static let numberGuess = """
    10 print "{clr}"
    20 print "*** number guessing game ***"
    30 print
    40 n=int(rnd(1)*100)+1
    50 g=0
    60 print "guess a number (1-100):"
    70 input a
    80 g=g+1
    90 if a<n then print "too low!":goto 60
    100 if a>n then print "too high!":goto 60
    110 print "correct! you got it in";g;"guesses!"
    120 print "play again? (y=1/n=0)"
    130 input p
    140 if p=1 then goto 10
    """

    static let mazeGenerator = """
    10 print "{clr}"
    20 for i=1 to 1000
    30 r=int(rnd(1)*2)
    40 if r=0 then print "{pur}/";
    50 if r=1 then print "{grn}\\";
    60 next i
    70 goto 70
    """

    static let starfield = """
    10 print "{clr}{blk}"
    20 poke 53281,0:poke 53280,0
    30 for i=1 to 80
    40 x=int(rnd(1)*40)
    50 y=int(rnd(1)*25)
    60 c=int(rnd(1)*3)
    70 if c=0 then poke 55296+y*40+x,1
    80 if c=1 then poke 55296+y*40+x,15
    90 if c=2 then poke 55296+y*40+x,12
    100 poke 1024+y*40+x,46
    110 next i
    120 rem twinkle
    130 x=int(rnd(1)*40)
    140 y=int(rnd(1)*25)
    150 p=peek(1024+y*40+x)
    160 if p<>46 then goto 130
    170 c=int(rnd(1)*3)
    180 if c=0 then poke 55296+y*40+x,1
    190 if c=1 then poke 55296+y*40+x,15
    200 if c=2 then poke 55296+y*40+x,12
    210 goto 130
    """

    static let sidSound = """
    10 print "{clr}"
    20 print "sid sound demo"
    30 print "playing a simple scale..."
    40 rem init sid
    50 for i=54272 to 54296:poke i,0:next i
    60 poke 54296,15:rem volume max
    70 poke 54277,9:rem attack/decay
    80 poke 54278,0:rem sustain/release
    90 rem c major scale frequencies
    100 data 68,69,77,78,86,87,97,34
    110 data 108,140,122,28,137,40,154,16
    120 for n=1 to 8
    130 read lo:read hi
    140 poke 54272,lo:poke 54273,hi
    150 poke 54276,17:rem gate on, triangle wave
    160 for t=1 to 500:next t
    170 poke 54276,16:rem gate off
    180 for t=1 to 100:next t
    190 next n
    200 print "done!"
    """

    static let fibonacci = """
    10 print "{clr}"
    20 print "fibonacci sequence"
    30 print "===================="
    40 print
    50 a=0:b=1
    60 for i=1 to 20
    70 print a
    80 c=a+b
    90 a=b:b=c
    100 next i
    110 print
    120 print "done! first 20 numbers."
    """
}
