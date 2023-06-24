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

async function worker(queue, rawResults, qoiResults) {
    while (queue.length > 0) {
        const file = queue.pop();
        if (!file.endsWith('.png')) {
            continue;
        }
        const { uncompressed, qoi, huffman } = JSON.parse((await $`../zig-out/bin/qohi ${file}`).stdout);
        const rawSaving = 100 * (uncompressed - huffman) / uncompressed;
        const qoiSaving = 100 * (qoi - huffman) / qoi;
        rawResults.push(rawSaving);
        qoiResults.push(qoiSaving);
    }
}

for (const c of categories) {
    console.log(`${c}:`);
    const pics = await glob(`${c}/*`);
    const rawSavings = [], qoiSavings = [];

    const workers = [];
    for (let i = 0; i < threads; i++) {
        workers.push(worker(pics, rawSavings, qoiSavings));
    }
    await Promise.all(workers);

    console.log(`  vs. raw: avg = ${colorValue(round(mean(rawSavings)))}%, σ = ${round(stddev(rawSavings))}pp`);
    console.log(`  vs. QOI: avg = ${colorValue(round(mean(qoiSavings)))}%, σ = ${round(stddev(qoiSavings))}pp`);

}
