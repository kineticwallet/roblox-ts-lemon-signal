export declare type SignalParameters<T> = Parameters<
	T extends unknown[] ? (...args: T) => never : T extends unknown ? (arg: T) => never : () => never
>;

export declare type SignalCallback<T> = (...args: SignalParameters<T>) => unknown;
export declare type SignalWait<T> = T extends unknown[] ? LuaTuple<T> : T;

export declare namespace Signal {
	interface Constructor {
		new <T>(): Signal<T>;
		readonly wrap: <T extends Callback>(signal: RBXScriptSignal<T>) => Signal<T>;
		readonly is: <O extends object>(object: O) => boolean;
	}
	export interface Connection {
		readonly Connected: boolean;
		Disconnect(): void;
		Reconnect(): void;
	}
}

export declare interface Signal<T> {
	readonly RBXScriptConnection?: RBXScriptConnection;

	Connect(fn: SignalCallback<T>): Signal.Connection;
	Once(fn: SignalCallback<T>): Signal.Connection;
	Wait(): SignalWait<T>;
	Fire(...args: SignalParameters<T>): void;
	DisconnectAll(): void;
	Destroy(): void;
}
