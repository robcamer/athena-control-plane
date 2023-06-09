
# Design Document Guidance

**Author:** Author
**Date:** date
**Status:** Draft

[Reference](https://www.industrialempathy.com/posts/design-docs-at-google/)

## Context and Scope

This section gives the reader a very rough overview of the landscape in which the new system is being built and what is actually being built. This isn’t a requirements doc. Keep it succinct! The goal is that readers are brought up to speed but some previous knowledge can be assumed and detailed info can be linked to. This section should be entirely focused on objective background facts

## Goals and Non-Goals

A short list of bullet points of what the goals of the system are, and, sometimes more importantly, what non-goals are. Note, that non-goals aren’t negated goals like “The system shouldn’t crash”, but rather things that could reasonably be goals, but are explicitly chosen not to be goals. A good example would be “ACID compliance”; when designing a database, you’d certainly want to know whether that is a goal or non-goal. And if it is a non-goal you might still select a solution that provides it, if it doesn’t introduce trade-offs that prevent achieving the goals.

## Overview

This section should start with an overview and then go into details.

Diagram: Visualization of what you are trying to do.

The design doc is the place to write down the trade-offs you made in designing your software. Focus on those trade-offs to produce a useful document with long-term value. That is, given the context (facts), goals and non-goals (requirements), the design doc is the place to suggest solutions and show why a particular solution best satisfies those goals.

The point of writing a document over a more formal medium is to provide the flexibility to express the problem set at hand in an appropriate manner. Because of this, there is no explicit guidance for how to actually describe the design.

Having said that, a few best practices and repeating topics have emerged that make sense for a large percentage of design docs:

### System Context Diagram

In many docs a system-context-diagram can be very useful. Such a diagram shows the system as part of the larger technical landscape and allows readers to contextualize the new design given its environment that they are already familiar with.

![Block diagram showing how various systems are related to each other. The actual text is just examples and not needed to be seen to understand the example.](https://www.industrialempathy.com/img/remote/2mPr0N-640w.webp)

Example of a system-context-diagram.

### APIs

If the system under design exposes an API, then sketching out that API is usually a good idea. In most cases, however, one should withstand the temptation to copy-paste formal interface or data definitions into the doc as these are often verbose, contain unnecessary detail and quickly get out of date. Instead focus on the parts that are relevant to the design and its trade-offs.

### Data Storage

Systems that store data should likely discuss how and in what rough form this happens. Similar to the advice on APIs, and for the same reasons, copy-pasting complete schema definitions should be avoided. Instead focus on the parts that are relevant to the design and its trade-offs.

### Code and Pseudo-Code

Design docs should rarely contain code, or pseudo-code except in situations where novel algorithms are described. As appropriate, link to prototypes that show the implementability of the design.

## Degree of Constraint

One of the primary factors that would influence the shape of a software design and hence the design doc, is the degree of constraint of the solution space.

On one end of the extreme is the “greenfield software project”, where all we know are the goals, and the solution can be whatever makes the most sense. Such a document may be wide-ranging, but it also needs to quickly define a set of rules that allow zooming in on a manageable set of solutions.

On the other end are systems where the possible solutions are very well defined, but it isn’t at all obvious how they could even be combined to achieve the goals. This may be a legacy system that is difficult to change and wasn’t designed to do what you want it to do or a library design that needs to operate within the constraints of the host programming language.

In this situation you may be able to enumerate all the things you can do relatively easily, but you need to creatively put those things together to achieve the goals. There may be multiple solutions, and none of them are really great, and hence such a document should focus on selecting the best way given all identified trade-offs.

## Alternatives considered

This section lists alternative designs that would have reasonably achieved similar outcomes. The focus should be on the trade-offs that each respective design makes and how those trade-offs led to the decision to select the design that is the primary topic of the document.

While it is fine to be succinct about solution that ended up not being selected, this section is one of the most important ones as it shows very explicitly why the selected solution is the best given the project goals and how other solutions, that the reader may be wondering about, introduce trade-offs that are less desirable given the goals.

## Engineering Fundamentals

This is where your organization can ensure that certain cross-cutting concerns such as security, privacy, and observability are always taken into consideration. These are often relatively short sections that explain how the design impacts the concern and how the concern is addressed. Teams should standardize what these concerns are in their case.

Due to their importance, Google projects are required to have a dedicated privacy design doc, and there are dedicated reviews for privacy and security. While the reviews are only required to be completed by the time a project launches, it is best practice to engage with privacy and security teams as early as possible to ensure that designs take them into account from the ground up. In case of dedicated docs for these topics, the central design doc can, of course, reference them instead of going into detail.

[Reference](https://www.industrialempathy.com/posts/design-docs-at-google/)
