# Atium
Metal wrapper and Rtmp client

> “I write these words in steel, for anything not set in metal cannot be trusted.”

### A metal wrapper

When I was surveying techs involving live streaming apps, the first decision was to use metal.

Next I need a framework for real-time image processing using metal. 

GPUImage looks nice. But it started as ObjC + OpenGL. 

The stack I'm looking for is Swift + metal, and although there are progress in GPUImage to move towards that, 

I decided to build one from scratch. 


### Rtmp client

As another effort in surveying live streaming, you need a Rtmp client. 

Looked into HaishinKit which is written in Swift. Unfortuately it seems to be a port from ActionScript or 

whatever non-sense Flash cooked up. It has so many inherited classes that I'm having hard time just navigating 

source files. Everyhing depends on something else. Hidden state after hidden state. 

It's a text-book example of why OOP is not as good as it promised. 

There are other frameworks written in ObjC. But I want Swift framework if I may need to customize it.

I decided to build one from scratch.


### Current status

Tested streaming to a nginx rtmp server hosted on mac. Also tested a simplest shader applying on live streaming. 

But I'll say these are proof of concepts at his stage. I may go back to improving it at later time.

They are put here primarily for viewing pleasure. 

A reminder that:

## Inheritance may hurt you.

## Swift when done right, is both elegant and powerful.




