#!/usr/bin/env zx

$.verbose = false;
const threads = 16;

await $`zig build -Doptimize=ReleaseSafe`;

cd('corpus');
const categories = await glob('*', { onlyDirectories: true });

function mean(array) {
    return array.reduce((a, b) => a + b) / array.length;
}

function stddev(array) {
    const arrayMean = mean(array);
    return Math.sqrt(mean(array.map(x => (x - arrayMean) ** 2)));
}

function round(n) {
    return Math.round(n * 100) / 100;
}

function colorValue(n) {
    return n > 0 ? chalk.green(n) : chalk.red(n);
}

function report(category, rawSavings, qoiSavings) {
    if (argv.markdown) {
        process.stdout.write(`| ${category} |`);
        process.stdout.write(` ${round(mean(rawSavings))} | ${round(stddev(rawSavings))} |`);
        process.stdout.write(` ${round(mean(qoiSavings))} | ${round(stddev(qoiSavings))} |`);
        console.log();
    } else {
        console.log(`  vs. raw: avg = ${colorValue(round(mean(rawSavings)))}%, \u03c3 = ${round(stddev(rawSavings))}pp`);
        console.log(`  vs. QOI: avg = ${colorValue(round(mean(qoiSavings)))}%, \u03c3 = ${round(stddev(qoiSavings))}pp`);
    }
}

function printProgress(progress) {
    if (argv.markdown) return;

    const width = 16;
    const chars = Math.round(width * progress);
    const blanks = width - chars;
    process.stdout.write('[');
    for (let i = 0; i < chars; i++) {
        process.stdout.write('=');
    }
    for (let i = 0; i < blanks; i++) {
        process.stdout.write(' ');
    }
    process.stdout.write(`]\x1b[${width + 2}D`);
}

async function worker(queue, rawResults, qoiResults) {
    while (queue.length > 0) {
        const file = queue.pop();
        if (!file.endsWith('.png')) {
            continue;
        }
        const { uncompressed, huffman } = JSON.parse((await $`../zig-out/bin/qohi ${file}`).stdout);
        const qoi = parseInt((await $`convert ${file} qoi:- | wc -c`).stdout) - 22;
        const rawSaving = 100 * (uncompressed - huffman) / uncompressed;
        const qoiSaving = 100 * (qoi - huffman) / qoi;
        rawResults.push(rawSaving);
        qoiResults.push(qoiSaving);
    }
}

if (argv.markdown) {
    console.log('| category | saving vs. raw (avg, %) | stddev (pp) | saving vs. qoi (avg, %) | stddev (pp) |');
    console.log('|----------|-------------------------|-------------|-------------------------|-------------|');
}

const overallRaw = [];
const overallQoi = [];

for (const c of categories) {
    if (!argv.markdown) {
        process.stdout.write(`${c}: `);
    }

    const pics = await glob(`${c}/*`);
    const totalLength = pics.length;
    const rawSavings = [], qoiSavings = [];

    const workers = [];
    for (let i = 0; i < threads; i++) {
        workers.push(worker(pics, rawSavings, qoiSavings));
    }

    while (pics.length > 0) {
        await sleep(250);
        printProgress((totalLength - pics.length) / totalLength);
    }

    await Promise.all(workers);

    if (!argv.markdown) {
        console.log();
    }
    report(c, rawSavings, qoiSavings);
    overallRaw.push(...rawSavings);
    overallQoi.push(...qoiSavings);
}

if (!argv.markdown) {
    console.log('total:');
}
report('total', overallRaw, overallQoi);
