---
layout: post
title: "Software Before Hardware"
date: 2026-10-12 22:31:47 -0400
author: Jamie Arlen
---

# Software Before Hardware.

I've designed a lot of hardware over the years. I'm actually pretty good at it. And every single time that one of those hardware projects had a software component the outcome seriously suffered because the software part never really got finished properly. 

The augmentation that is coming from working with the Cline harness and various open-weight models is leading me towards the idea that I can go ahead and build the hardware while the software was being developed. 

And then I woke up and faced the music... Augmentation is not a guarantee of success. If you read The Research Assistant's last blog entry, you'll learn that he spent most of the day chasing TWO BYTES. And that was *with* a few inspirational / intuition moments of help from me. 

## Decisions That Hurt My Soul.

The Software has to come before the Hardware. It must. And it's even worse than that. In order to allow the creation of the firmware and CP/M side software, we were going to need an emulator. The thing is... having the ability to programmatically drive MAME has been game-changing in this work. And so I authorized the creation of a proper emulation environment. That means a *new* MAME machine type *osborne1nx* that has a virtual interposer and already has the Adaptec ACB-4000 and a selection of ST506 drives. That work is already available in this repo and we're probably going to try to push it upstream and see if we can get it officially into MAME - that'd be pretty cool. And then a very twisty part... MAME can handle emulating the Z80 and its surroundings but I need something that can emulate the RP2354 that is the microcontroller we'll use for the interposer card. Open Source to the RESCUE! [PicoEm](https://github.com/0x4D44/picoem) is a cycle accurate implementation of the Raspberry Pi Pico family of microcontrollers written in Rust. And we've got an issue to figure out how to (software) wire up the PicoEm to the MAME Z80 memory space. It'll be a fantastic development environment that will let other smart people out there come up with new personalities to add to the interposer and the Final Boss - the O1NEXT. 

## Old Dog / New Tricks

The way I've described my ability to work with actual software engineers in that architect / pain in the ass mode doesn't really work with Open Source projects. I've been using Open Source software every day since about 1992 - my first Linux machine was Slackware on 1.2mb floppies because my x86 computer _didn't have a 3.5" floppy drive_. And after 33+ years of using Open Source software to run my life, run a few businesses, deliver Platform as a Service at Heroku and Aiven... the number of real contributions I've made is painfully low. I've _funded_ lots of Open Source (for 5 years, LibreS/WAN's maintainer worked for me and I gave him the time to maintain it on my dime... well... out of my budget anyways). Across everything that has come out of budgets I controlled at the time, it's definitely millions of dollars and that does help me sleep at night - I fought for Libre and I fought for Beer. But I haven't really contributed much in the way of code. 

I know that some Open Source projects have REALLY strict rules about how AI is used and I will always declare exactly how the code I'm submitting came into existence. I'm still an infosec / GRC wonk at heart and SBoM is real to me - knowing the provenance of code _matters_.

I've got bug fixes for *cpmtools* (Kaypro IV disk format fails), *LibDsk* (assumption about default formats aren't explicit - this is back port from 1.5.x-unstable to 1.4.x-stable so that it ships to _homebrew_), and MAME (bug fixes and also the whole _osborne1nx_ machine). And I'm sure there will be more. 

And that's all on top of this entire repo which will have host-side (python / bash) software, RP2040/2350 firmware, CP/M software - all MIT licensed. And Creative Commons NCBYSA hardware designs and 3d print files. Open. Ready for anyone to pick up and use or modify to their needs - while requiring them to give it all back to the same community they got it from. We all stand on the shoulders of giants (this whole project has a singular foundation that stands on Lee Felsenstein and Adam Osborne) and maybe someone will see my shoulders as worthy of being stood on too. 

Because that would be _really awesome_.