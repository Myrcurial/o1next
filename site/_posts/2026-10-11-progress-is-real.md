---
layout: post
title: "Progress is Real"
author: Jamie Arlen
---

# Progress is Real.

The thing that is currently driving me crazy is how so many projects use AI in a way that is so incredibly confidently wrong and sloppy. There's a valid reason for the "AI Slopware" rants that show up in basically every social media posting, especially ones that are part of a hobby - because a lot of it is genuinely crap. 

I stand by my statement: Augmentation is the pattern that is successful in these sorts of adventures. 

One of my 'features' is that I'm really good at systems level thinking and synthesis of ideas. I do well as the "architect" on the team - creative, thinking outside the box, aware of engineering realities but also willing to push the engineers to figure out the actual possibilities, and then buy extra coffee and donuts for the actual construction people who have to bring my ideas to life. 

I've managed software development teams on and off for the last 30 years. The biggest open secret is that I am just not a good programmer. Really not good. Don't run my code in production anywhere. I used to do sysadmin work and even my bash scripts were notoriously awful. But I'm really good at explaining what I want built and then giving the engineers the room to do it right without ever meddling in the detail. I'm good at spell checking interfaces (and the aforementioned donuts and coffee.)

# The Research Assistant.

As you learned in the last post, I'm working with an AI harness and some models on this project and it's surprising how effectively it's working when I interact with the AI the same way I used to interact with software engineers. The thing that is important though is that I don't automatically assume the AI is correct - or even on the right track. Together we've caught all kinds of issues caused by mis-understanding, failure to see what's right in front of your face, or just general lack of awareness that a simple Google search would have fixed. 

We're getting very close to the end of the research phase (only two open issues left) and we've gotten pretty far on the design of the first of the standalone upgrades but the amount of things we've accomplished is even more than that. 

# It's all Side Quests.

One thing that is abundantly clear - both The Research Assistant and I have raging cases of ADHD - the number of times the transcript has the phrase "side quest" is astonishingly high. Well... not astonishing if you know me. And the thing that matters is that every one of the side quests has lead directly to positive outcomes. 

*Side Quests*
- we should have a website that we can post working blog entries to as proof of work
- we should make it look cool - grab the colours of the OCC1A case! 
- is it a project without a logo? nope - get a logo! 
- it's not really accurate if it doesn't use the actual Osborne 1 font
- but the font is different depending on whether it's in 52 / 80 / 104 character mode
- so we really need three Osborne 1 fonts
- and we can let the website viewers choose which way they want to see the website
- it's basically SCREEN PAC for the website! 
- Ok, we've gathered all of this reasearch that's buried in the repo
- Easy enough to put it on the website
- And generate the whole thing as a PDF
- What do you mean we have 183+ pages of carefully assembled evidence and research with full provenance? 
- This is starting to look not just possible, but even easy - need a list of "what we're going to ship"
- Damn. That's a lot of things - really? Yes, we've got a plan for all of them and even the beginnings of hardware and firmware for these things! 
- ... you get the idea

# Fun Side Quest Outcomes

There's lots but here's a few to make you smile: 
* not super well laid out yet, but so many [utilities and tools](https://github.com/Myrcurial/o1nextgen/tree/main/tools)
* [Osborne 1 font files](https://github.com/Myrcurial/o1nextgen/tree/main/site/assets/fonts)
* the [full design](https://github.com/Myrcurial/o1nextgen/blob/main/docs/floppy-adapter-design.md) for an adapter that makes GoTek drives easier to use based on Richard Loxley's project
* Everything you ever wanted to know about [Osborne 1 + MAME](https://github.com/Myrcurial/o1nextgen/blob/main/docs/mame-emulation.md) (seriously) (even OZROM on MAME)

And we're getting getting started. 

# Next?

We're going to finish the research and see if we can get engineering samples of the three external devices done in the next month (if not faster) -- that's the [USB Keyboard input adapter](https://myrcurial.github.io/o1nextgen/hardware/keyboard-interface/), the [WiFi COMM PAC](https://myrcurial.github.io/o1nextgen/hardware/external-modem/), and the [Drive C Reproduction](https://myrcurial.github.io/o1nextgen/hardware/drive-c/). 